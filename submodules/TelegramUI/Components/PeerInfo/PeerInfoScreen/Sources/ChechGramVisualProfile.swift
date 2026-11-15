import Foundation

/// A purely visual profile that only ChechGram clients display.
/// Real Telegram data is never changed: the overlay is drawn on top of it locally.
struct ChechGramVisualProfile: Codable, Equatable {
    struct Gift: Codable, Equatable {
        var title: String
        var giftId: String?
        var number: Int?
    }

    var phone: String
    var username: String
    var gifts: [Gift]
}

/// Reads visual profiles from the ChechGram server and caches them.
/// Reads are synchronous (cache only); misses trigger one background fetch per peer per run.
final class ChechGramVisualProfileStore {
    static let shared = ChechGramVisualProfileStore()

    /// Address of the ChechGram server on the VPS. Change it to the real host.
    static let baseUrl = "https://chechgram.example.com"

    private let lock = NSLock()
    private var cache: [Int64: ChechGramVisualProfile?] = [:]
    private var inFlight = Set<Int64>()

    private init() {
    }

    /// Cached overlay for a user id, or nil when there is none (or it has not arrived yet).
    func profile(forUserId id: Int64) -> ChechGramVisualProfile? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let entry = self.cache[id] {
            return entry
        }
        return nil
    }

    /// Forgets what is cached for the id so the next profile open fetches it again.
    func invalidate(userId id: Int64) {
        self.lock.lock()
        self.cache[id] = nil
        self.lock.unlock()
    }
    
    /// Starts one fetch for the id if nothing is known about it yet.
    /// `completion` runs on the main queue only if the answer contains a profile.
    func fetchIfNeeded(userId id: Int64, completion: @escaping () -> Void) {
        self.lock.lock()
        if self.cache[id] != nil || self.inFlight.contains(id) {
            self.lock.unlock()
            return
        }
        self.inFlight.insert(id)
        self.lock.unlock()

        guard let url = URL(string: ChechGramVisualProfileStore.baseUrl + "/v1/profiles?ids=\(id)") else {
            self.finish(id: id, profile: nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var result: ChechGramVisualProfile?
            if let data = data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let profiles = object["profiles"] as? [String: Any],
               let raw = profiles[String(id)] as? [String: Any] {
                result = ChechGramVisualProfileStore.parse(raw)
            }
            self?.finish(id: id, profile: result)
            if result != nil {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }.resume()
    }

    private func finish(id: Int64, profile: ChechGramVisualProfile?) {
        self.lock.lock()
        self.cache[id] = .some(profile)
        self.inFlight.remove(id)
        self.lock.unlock()
    }

    private static func parse(_ raw: [String: Any]) -> ChechGramVisualProfile {
        let phone = (raw["phone"] as? String ?? "").filter { $0.isNumber }
        let username = raw["username"] as? String ?? ""
        var gifts: [ChechGramVisualProfile.Gift] = []
        for item in raw["gifts"] as? [[String: Any]] ?? [] {
            gifts.append(ChechGramVisualProfile.Gift(
                title: item["title"] as? String ?? "",
                giftId: item["giftId"] as? String,
                number: item["number"] as? Int
            ))
        }
        return ChechGramVisualProfile(phone: phone, username: username, gifts: gifts)
    }
}
