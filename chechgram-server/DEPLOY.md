# ChechGram: запуск от начала до айфона

## 1. Сервер на VPS

Нужен VPS с Ubuntu/Debian и доменом (или поддоменом), например `cg.example.com`, который указывает на IP VPS (A-запись).

```bash
# Node 20+
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs nginx certbot python3-certbot-nginx

# код сервера
sudo mkdir -p /opt/chechgram /var/lib/chechgram
# скопируй сюда server.js (scp или git clone) -> /opt/chechgram/server.js
```

Служба systemd `/etc/systemd/system/chechgram.service`:

```ini
[Unit]
Description=ChechGram server
After=network.target

[Service]
Environment=PORT=8787
Environment=DATA_FILE=/var/lib/chechgram/data.json
ExecStart=/usr/bin/node /opt/chechgram/server.js
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now chechgram
curl http://127.0.0.1:8787/health      # должно вернуть {"ok":true}
```

nginx `/etc/nginx/sites-available/chechgram` (замени домен):

```nginx
server {
    server_name cg.example.com;
    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/chechgram /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d cg.example.com     # включает https
curl https://cg.example.com/health
```

iOS не пускает обычный http, поэтому https обязателен.

## 2. Адрес сервера в приложении

В файле `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ChechGramVisualProfile.swift`
замени `https://chechgram.example.com` на свой домен.

## 3. Сборка в GitHub Actions

1. Репозиторий `timur850/Telegram-iOS` → Settings → Secrets and variables → Actions → New repository secret.
2. Добавь `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` (берутся на https://my.telegram.org → API development tools).
3. Actions → «Build iOS (test, unsigned)» → Run workflow → ветка `chechgram-visual-profile`.
4. Жди окончания (может быть несколько часов). Готовый `.ipa` будет в Artifacts: `Telegram-unsigned-ipa`.

## 4. Установка на айфон (без Мака)

1. На Windows поставь Sideloadly.
2. Подключи айфон кабелем, перетащи `.ipa` в Sideloadly, введи свой Apple ID.
3. На айфоне: Настройки → Основные → VPN и управление устройством → доверять своему Apple ID.
4. Бесплатная подпись держится 7 дней, потом приложение надо переустановить.

## 5. Проверка

Открой приложение → Настройки → ChechGram. Задай баланс, номер, юзернейм, купи подарок. Другой пользователь ChechGram увидит их у тебя в профиле с пометкой ChechGram.
