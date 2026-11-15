// ChechGram visual-profile server.
// Stores a purely visual profile (phone, username, gifts) per Telegram peer id.
// Only ChechGram clients read it; regular Telegram is unaffected.
// Zero dependencies: Node >= 18.  Run: PORT=8787 DATA_FILE=./data.json node server.js
"use strict";

const http = require("node:http");
const fs = require("node:fs");
const crypto = require("node:crypto");

const PORT = Number(process.env.PORT || 8787);
const DATA_FILE = process.env.DATA_FILE || "./data.json";
const MAX_GIFTS = 30;
const MAX_IDS_PER_QUERY = 100;

// { [peerId]: { tokenHash, profile: {phone, username, gifts[], updatedAt} } }
let db = {};
try {
  db = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
} catch (_) {
  db = {};
}

let saveTimer = null;
function save() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    const tmp = DATA_FILE + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(db));
    fs.renameSync(tmp, DATA_FILE);
  }, 200);
}

const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");

function send(res, code, body) {
  const data = JSON.stringify(body);
  res.writeHead(code, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(data),
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
  });
  res.end(data);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > 64 * 1024) {
        reject(new Error("too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => {
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

function authPeer(req) {
  const h = req.headers["authorization"] || "";
  const m = /^Bearer\s+(\d+):([0-9a-f]{64})$/.exec(h);
  if (!m) return null;
  const rec = db[m[1]];
  if (!rec) return null;
  const a = Buffer.from(sha(m[2]), "hex");
  const b = Buffer.from(rec.tokenHash, "hex");
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  return m[1];
}

const str = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : "");

function cleanProfile(input) {
  const gifts = Array.isArray(input.gifts) ? input.gifts.slice(0, MAX_GIFTS) : [];
  return {
    phone: str(input.phone, 32),
    username: str(input.username, 64).replace(/^@/, ""),
    gifts: gifts.map((g) => ({
      title: str(g && g.title, 64),
      // Telegram gift / sticker id if the client wants to render the real art.
      giftId: str(g && g.giftId, 32),
      number: Number.isFinite(g && g.number) ? g.number : 0,
    })),
    updatedAt: Date.now(),
  };
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://x");
    if (req.method === "OPTIONS") return send(res, 204, {});

    if (url.pathname === "/health") return send(res, 200, { ok: true });

    // Claim a peer id. Returns a secret token the client keeps; shown once.
    if (req.method === "POST" && url.pathname === "/v1/register") {
      const body = await readJson(req);
      const peerId = String(body.peerId || "");
      if (!/^\d{1,20}$/.test(peerId)) return send(res, 400, { error: "bad peerId" });
      if (db[peerId]) return send(res, 409, { error: "already registered" });
      const token = crypto.randomBytes(32).toString("hex");
      db[peerId] = { tokenHash: sha(token), profile: null };
      save();
      return send(res, 200, { peerId, token });
    }

    // Own profile: set / clear.
    if (url.pathname === "/v1/profile") {
      const peerId = authPeer(req);
      if (!peerId) return send(res, 401, { error: "unauthorized" });
      if (req.method === "PUT") {
        db[peerId].profile = cleanProfile(await readJson(req));
        save();
        return send(res, 200, { ok: true });
      }
      if (req.method === "DELETE") {
        db[peerId].profile = null;
        save();
        return send(res, 200, { ok: true });
      }
      if (req.method === "GET") return send(res, 200, { profile: db[peerId].profile });
    }

    // Batch read: ?ids=1,2,3 -> { "1": {...} } (only ids that have a profile)
    if (req.method === "GET" && url.pathname === "/v1/profiles") {
      const ids = String(url.searchParams.get("ids") || "")
        .split(",")
        .filter((s) => /^\d{1,20}$/.test(s))
        .slice(0, MAX_IDS_PER_QUERY);
      const out = {};
      for (const id of ids) {
        if (db[id] && db[id].profile) out[id] = db[id].profile;
      }
      return send(res, 200, { profiles: out });
    }

    send(res, 404, { error: "not found" });
  } catch (e) {
    send(res, 400, { error: "bad request" });
  }
});

server.listen(PORT, () => console.log("chechgram-server on :" + PORT));
