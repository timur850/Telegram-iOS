# ChechGram server

Хранит визуальный профиль (номер +888, юзернейм, подарки) по Telegram ID. Читают его только клиенты ChechGram.

Запуск на VPS (Node 18+, без зависимостей):

    PORT=8787 DATA_FILE=/var/lib/chechgram/data.json node server.js

Рекомендуется держать за nginx с HTTPS и запускать через systemd или pm2.
После этого впиши адрес в `ChechGramVisualProfileStore.baseUrl`
(`submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ChechGramVisualProfile.swift`).

API:
- `POST /v1/register {peerId}` — занять ID, вернёт секретный token (один раз)
- `PUT /v1/profile` (Authorization: Bearer `<peerId>:<token>`) `{phone, username, gifts:[{title, giftId, number}]}`
- `DELETE /v1/profile`
- `GET /v1/profiles?ids=1,2,3` — публичное чтение
