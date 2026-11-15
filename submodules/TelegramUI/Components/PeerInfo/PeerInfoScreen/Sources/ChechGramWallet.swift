import Foundation
import UIKit
import Display
import AccountContext
import TelegramPresentationData
import PromptUI
import SwiftSignalKit
import TelegramCore

/// A gift that can be "bought" with the visual wallet. Purely cosmetic.
private struct ChechGramCatalogGift {
    let title: String
    let price: Double
    let currency: String
    let giftId: String
}

/// Collectible gifts are not in Telegram's regular catalog, so they are listed here by hand.
/// Prices are rough and only matter for the visual balance.
private let chechGramCollectibles: [ChechGramCatalogGift] = [
    ChechGramCatalogGift(title: "Plush Pepe", price: 3000, currency: "ton", giftId: ""),
    ChechGramCatalogGift(title: "Heart Locket", price: 600, currency: "ton", giftId: ""),
    ChechGramCatalogGift(title: "Durov's Cap", price: 400, currency: "ton", giftId: ""),
    ChechGramCatalogGift(title: "Precious Peach", price: 250, currency: "ton", giftId: ""),
    ChechGramCatalogGift(title: "Loot Bag", price: 100, currency: "ton", giftId: "")
]

/// The owner's own visual profile, including the private play-money wallet.
private struct ChechGramOwnState {
    var stars: Double
    var ton: Double
    var phone: String
    var username: String
    var giftTitles: [String]
}

private enum ChechGramApi {
    static func tokenKey(_ peerId: Int64) -> String {
        return "chechgram.token.\(peerId)"
    }
    
    /// Sends a request and reports (status code, JSON object) on the main queue.
    static func call(path: String, method: String, authorization: String?, body: [String: Any]?, completion: @escaping (Int, [String: Any]?) -> Void) {
        guard let url = URL(string: ChechGramVisualProfileStore.baseUrl + path) else {
            completion(0, nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10.0
        if let authorization = authorization {
            request.setValue("Bearer " + authorization, forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var object: [String: Any]?
            if let data = data {
                object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            DispatchQueue.main.async {
                completion(code, object)
            }
        }.resume()
    }
    
    /// Returns the "peerId:token" authorization string, registering the id on first use.
    static func authorization(peerId: Int64, completion: @escaping (String?) -> Void) {
        if let token = UserDefaults.standard.string(forKey: tokenKey(peerId)) {
            completion("\(peerId):\(token)")
            return
        }
        call(path: "/v1/register", method: "POST", authorization: nil, body: ["peerId": String(peerId)]) { code, object in
            if code == 200, let token = object?["token"] as? String {
                UserDefaults.standard.set(token, forKey: tokenKey(peerId))
                completion("\(peerId):\(token)")
            } else {
                completion(nil)
            }
        }
    }
    
    static func loadOwn(peerId: Int64, completion: @escaping (ChechGramOwnState?) -> Void) {
        authorization(peerId: peerId) { auth in
            guard let auth = auth else {
                completion(nil)
                return
            }
            call(path: "/v1/profile", method: "GET", authorization: auth, body: nil) { code, object in
                guard code == 200 else {
                    completion(nil)
                    return
                }
                let profile = object?["profile"] as? [String: Any] ?? [:]
                let gifts = profile["gifts"] as? [[String: Any]] ?? []
                completion(ChechGramOwnState(
                    stars: profile["stars"] as? Double ?? 0.0,
                    ton: profile["ton"] as? Double ?? 0.0,
                    phone: profile["phone"] as? String ?? "",
                    username: profile["username"] as? String ?? "",
                    giftTitles: gifts.compactMap { $0["title"] as? String }
                ))
            }
        }
    }
    
    static func update(peerId: Int64, fields: [String: Any], completion: @escaping (Bool) -> Void) {
        authorization(peerId: peerId) { auth in
            guard let auth = auth else {
                completion(false)
                return
            }
            call(path: "/v1/profile", method: "PUT", authorization: auth, body: fields) { code, _ in
                ChechGramVisualProfileStore.shared.invalidate(userId: peerId)
                completion(code == 200)
            }
        }
    }
    
    static func buy(peerId: Int64, gift: ChechGramCatalogGift, completion: @escaping (Int) -> Void) {
        authorization(peerId: peerId) { auth in
            guard let auth = auth else {
                completion(0)
                return
            }
            let body: [String: Any] = ["title": gift.title, "price": gift.price, "currency": gift.currency, "giftId": gift.giftId]
            call(path: "/v1/buy", method: "POST", authorization: auth, body: body) { code, _ in
                ChechGramVisualProfileStore.shared.invalidate(userId: peerId)
                completion(code)
            }
        }
    }
}

private func formatChechGramAmount(_ value: Double) -> String {
    if value == value.rounded() {
        return String(Int64(value))
    }
    return String(value)
}

/// Settings ▸ ChechGram: edit the visual profile and play-money wallet.
func presentChechGramMenu(context: AccountContext, controller: ViewController) {
    let peerId = context.account.peerId.id._internalGetInt64Value()
    ChechGramApi.loadOwn(peerId: peerId) { [weak controller] state in
        guard let controller = controller else {
            return
        }
        guard let state = state else {
            showChechGramSheet(context: context, controller: controller, title: "Нет связи с сервером ChechGram. Проверь адрес сервера.", buttons: [])
            return
        }
        showChechGramMenu(context: context, controller: controller, peerId: peerId, state: state)
    }
}

private func showChechGramSheet(context: AccountContext, controller: ViewController, title: String, buttons: [(String, () -> Void)]) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for (buttonTitle, handler) in buttons {
        items.append(ActionSheetButtonItem(title: buttonTitle, color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            handler()
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    controller.present(actionSheet, in: .window(.root))
}

private func showChechGramMenu(context: AccountContext, controller: ViewController, peerId: Int64, state: ChechGramOwnState) {
    let header = "ChechGram · визуальный профиль\n⭐ \(formatChechGramAmount(state.stars))  ·  TON \(formatChechGramAmount(state.ton))\nПодарков: \(state.giftTitles.count)\nВсё это видно только в ChechGram и помечено как визуальное."
    
    let reopen: () -> Void = { [weak controller] in
        if let controller = controller {
            presentChechGramMenu(context: context, controller: controller)
        }
    }
    
    let ask: (String, String, String, @escaping (String) -> Void) -> Void = { [weak controller] text, value, placeholder, apply in
        let prompt = promptController(context: context, text: text, value: value, placeholder: placeholder, apply: { result in
            if let result = result {
                apply(result.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        })
        controller?.present(prompt, in: .window(.root))
    }
    
    showChechGramSheet(context: context, controller: controller, title: header, buttons: [
        ("Задать баланс ⭐", {
            ask("Сколько звёзд показывать на балансе?", formatChechGramAmount(state.stars), "10000", { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value >= 0 else {
                    return
                }
                ChechGramApi.update(peerId: peerId, fields: ["stars": value], completion: { _ in
                    reopen()
                })
            })
        }),
        ("Задать баланс TON", {
            ask("Сколько TON показывать на балансе?", formatChechGramAmount(state.ton), "100", { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value >= 0 else {
                    return
                }
                ChechGramApi.update(peerId: peerId, fields: ["ton": value], completion: { _ in
                    reopen()
                })
            })
        }),
        ("Купить подарок", {
            showChechGramCatalog(context: context, controller: controller, peerId: peerId, reopen: reopen)
        }),
        ("Визуальный номер", {
            ask("Номер, который увидят пользователи ChechGram (например +888 0123 4567). Пусто — убрать.", state.phone, "+888", { text in
                ChechGramApi.update(peerId: peerId, fields: ["phone": text], completion: { _ in
                    reopen()
                })
            })
        }),
        ("Визуальный юзернейм", {
            ask("Юзернейм, который увидят пользователи ChechGram. Пусто — убрать.", state.username, "username", { text in
                ChechGramApi.update(peerId: peerId, fields: ["username": text], completion: { _ in
                    reopen()
                })
            })
        })
    ])
}

private func showChechGramCatalog(context: AccountContext, controller: ViewController, peerId: Int64, reopen: @escaping () -> Void) {
    // Real catalog: every regular gift Telegram currently offers, with its real price in Stars.
    let _ = (context.engine.payments.cachedStarGifts()
    |> take(1)
    |> deliverOnMainQueue).start(next: { [weak controller] gifts in
        guard let controller = controller else {
            return
        }
        var catalog: [ChechGramCatalogGift] = chechGramCollectibles
        for gift in gifts ?? [] {
            if case let .generic(info) = gift {
                catalog.append(ChechGramCatalogGift(title: info.title ?? "Gift", price: Double(info.price), currency: "stars", giftId: String(info.id)))
            }
        }
        
        var buttons: [(String, () -> Void)] = []
        for gift in catalog {
            let price = gift.currency == "ton" ? "\(formatChechGramAmount(gift.price)) TON" : "\(formatChechGramAmount(gift.price)) ⭐"
            buttons.append(("\(gift.title) — \(price)", { [weak controller] in
                ChechGramApi.buy(peerId: peerId, gift: gift, completion: { code in
                    guard let controller = controller else {
                        return
                    }
                    if code == 200 {
                        reopen()
                    } else {
                        let message = code == 402 ? "Не хватает визуального баланса." : "Не удалось купить подарок."
                        showChechGramSheet(context: context, controller: controller, title: message, buttons: [])
                    }
                })
            }))
        }
        showChechGramSheet(context: context, controller: controller, title: "Все подарки (оплата визуальным балансом)", buttons: buttons)
    })
}
