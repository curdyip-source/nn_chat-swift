//
//  ComposerPastedItemsParser.swift
//  NufNaf Chat
//
//  Разбор вставленного в поиск композера списка позиций. Понимаем два формата.
//
//  Заказ с сайта — количество и цена в конце строки:
//
//      1. Kajal: Dahab 100ml 1 x 8224₽ = 8224₽
//      2. Gucci: Flora Gorgeous Orchid 100ml tester 1 x 5619₽ = 5619₽
//
//  Выгрузка таблицей — количество в начале, цена отдельной колонкой (через таб):
//
//      1 шт⇥Гель для душа Amouage Guidance 360 ml⇥64
//      12 шт⇥Chanel Coco Mademoiselle, Eau De Parfum, 1,5 мл⇥7
//
//  Тот же вид, но колонки разделены звёздочкой:
//
//      1 шт. *  Armand Basi: In Red edp 100ml tester *  2159 ₽
//      1 шт. *  Estee Lauder: Beautiful Belle 100ml *  6784 ₽
//
//  Первый формат — зеркало `nn_price/backend/app/ingest/site_order_parser.py`: одна
//  и та же вставка должна давать одинаковые позиции и в письме, и руками из
//  приложения.
//

import Foundation

/// Позиция вставленного списка.
nonisolated struct ComposerPastedItem: Equatable {
    let name: String
    let quantity: Int
    /// Цена в формате API («8224.00»). nil — в строке цены не было.
    let price: String?
    /// Код валюты по знаку в строке («RUB»/«USD»/«EUR»). nil — валюта не указана.
    let currencyCode: String?
}

nonisolated enum ComposerPastedItemsParser {
    static func parse(_ text: String) -> [ComposerPastedItem] {
        let normalized = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return normalized
            .components(separatedBy: "\n")
            .compactMap(parseLine)
    }

    // MARK: - Строка

    // Позиция: «[N.] наименование КОЛ x ЦЕНА[валюта] [= сумма]».
    // Наименование нежадное, чтобы «КОЛ x ЦЕНА» отрезалось с конца, даже если само
    // наименование заканчивается числом («… Dahab 100ml 1 x 8224₽»). Умножение —
    // латинская x, кириллическая х, × или *.
    private static let itemRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:\d+\s*[.)]\s*)?(?<name>.+?)\s+(?<qty>\d+)\s*[xх×*]\s*(?<price>[\d\s.,]+?)\s*(?<currency>₽|руб\.?|р\.|rub|\$|usd|€|eur)?\s*(?:=.*)?$"#,
        options: [.caseInsensitive]
    )

    // Позиция таблицей: «КОЛ шт<таб>наименование<таб>ЦЕНА». Единица измерения
    // необязательна, но тогда за количеством обязан идти таб — иначе «1.» из
    // нумерации первого формата читалось бы как количество.
    private static let quantityPrefixRegex = try? NSRegularExpression(
        pattern: #"^\s*(?<qty>\d+)\s*(?:шт|штук[аи]?|pcs|pc|ед)\.?\s*[-–—:]?[ \t]+(?<rest>\S.*)$"#,
        options: [.caseInsensitive]
    )

    private static let quantityTabRegex = try? NSRegularExpression(
        pattern: #"^\s*(?<qty>\d+)[ \t]*\t[ \t]*(?<rest>\S.*)$"#
    )

    // Цена отдельной колонкой: отделяем её только явным разделителем (таб, 2+ пробела
    // или «*»), чтобы не спутать с числами внутри наименования («… 100 мл»).
    private static let columnPriceRegex = try? NSRegularExpression(
        pattern: #"^(?<name>.*\S)(?:[ \t]*[*•|][ \t]*|[ \t]*\t[ \t]*| {2,})(?<price>\d[\d\s.,]*?)\s*(?<currency>₽|руб\.?|р\.|rub|\$|usd|€|eur)?\s*$"#,
        options: [.caseInsensitive]
    )

    // Тот же хвост, но без явного разделителя: на случай, если табы потерялись при
    // копировании. Срабатывает только внутри формата «КОЛ шт …», и цена обязана
    // быть последним словом строки, иначе наименование не трогаем.
    private static let looseTrailingPriceRegex = try? NSRegularExpression(
        pattern: #"^(?<name>.*\S)\s+(?<price>\d+(?:[.,]\d+)?)\s*(?<currency>₽|руб\.?|р\.|rub|\$|usd|€|eur)?\s*$"#,
        options: [.caseInsensitive]
    )

    private static let fieldRegex = try? NSRegularExpression(pattern: #"^(?<key>[^:]{1,40}?)\s*:\s*(?<value>.*)$"#)

    private static let urlRegex = try? NSRegularExpression(pattern: #"https?\s*://|www\."#, options: [.caseInsensitive])

    private static let numberingRegex = try? NSRegularExpression(pattern: #"^\s*\d+\s*[.)]\s*"#)

    private static let leadingSeparatorRegex = try? NSRegularExpression(pattern: #"^[ \t]*[*•|][ \t]*"#)

    private static func parseLine(_ rawLine: String) -> ComposerPastedItem? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }

        // Позицию разбираем ДО «ключ: значение»: в наименовании бывает двоеточие
        // («1. Versace: Eros Flame 100ml 1 x 6690₽»).
        if let item = matchQuantityFirstItem(line) ?? matchItem(line) {
            return item
        }

        guard !isServiceLine(line) else { return nil }

        // Строка без «КОЛ x ЦЕНА» — это просто наименование: цену менеджер проставит
        // в корзине (без цены композер всё равно не даст создать заказ).
        let name = cleanedName(stripNumbering(line))
        guard !name.isEmpty else { return nil }
        return ComposerPastedItem(name: name, quantity: 1, price: nil, currencyCode: nil)
    }

    /// «1 шт⇥Гель для душа Amouage Guidance 360 ml⇥64» -> позиция.
    private static func matchQuantityFirstItem(_ line: String) -> ComposerPastedItem? {
        let range = NSRange(line.startIndex..., in: line)
        let match = quantityPrefixRegex?.firstMatch(in: line, range: range)
            ?? quantityTabRegex?.firstMatch(in: line, range: range)

        guard let match,
              let rawQuantity = capture(match, "qty", in: line),
              let rest = capture(match, "rest", in: line) else {
            return nil
        }

        let (name, price, currencyCode) = splitTrailingPrice(stripLeadingSeparator(rest))
        guard !name.isEmpty else { return nil }

        return ComposerPastedItem(
            name: name,
            quantity: max(1, Int(rawQuantity) ?? 1),
            price: price,
            currencyCode: currencyCode
        )
    }

    /// Отрезает от «наименование … цена» ценовую колонку. Цены может не быть —
    /// тогда вся строка идёт наименованием, а цену дозаполнят в корзине.
    private static func splitTrailingPrice(_ rest: String) -> (name: String, price: String?, currencyCode: String?) {
        let range = NSRange(rest.startIndex..., in: rest)
        for regex in [columnPriceRegex, looseTrailingPriceRegex] {
            guard let match = regex?.firstMatch(in: rest, range: range),
                  let rawName = capture(match, "name", in: rest),
                  let rawPrice = capture(match, "price", in: rest),
                  let price = normalizedPrice(rawPrice) else {
                continue
            }
            let name = cleanedName(rawName)
            guard !name.isEmpty else { continue }
            return (name, price, currencyCode(for: capture(match, "currency", in: rest)))
        }
        return (cleanedName(rest), nil, nil)
    }

    private static func matchItem(_ line: String) -> ComposerPastedItem? {
        guard let itemRegex,
              let match = itemRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let rawName = capture(match, "name", in: line),
              let rawQuantity = capture(match, "qty", in: line),
              let rawPrice = capture(match, "price", in: line),
              let price = normalizedPrice(rawPrice) else {
            return nil
        }

        let name = cleanedName(rawName)
        guard !name.isEmpty else { return nil }

        return ComposerPastedItem(
            name: name,
            quantity: max(1, Int(rawQuantity) ?? 1),
            price: price,
            currencyCode: currencyCode(for: capture(match, "currency", in: line))
        )
    }

    /// Строки шапки письма/списка («Итого: 6690₽», «Телефон: …») в корзину не идут.
    private static func isServiceLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if lowercased.hasPrefix("новый заказ") { return true }

        let range = NSRange(line.startIndex..., in: line)
        if urlRegex?.firstMatch(in: line, range: range) != nil { return true }

        guard let fieldRegex,
              let match = fieldRegex.firstMatch(in: line, range: range),
              let key = capture(match, "key", in: line) else {
            return false
        }
        return serviceKeys.contains(key.trimmingCharacters(in: .whitespaces).lowercased())
    }

    // MARK: - Хелперы

    private static func capture(_ match: NSTextCheckingResult, _ name: String, in line: String) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return nil }
        return String(line[swiftRange])
    }

    private static func stripNumbering(_ line: String) -> String {
        guard let numberingRegex else { return line }
        return numberingRegex.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: ""
        )
    }

    private static func cleanedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: " .·—-*•|\t"))
    }

    /// «*  Armand Basi: …» -> «Armand Basi: …»: разделитель колонок после количества.
    private static func stripLeadingSeparator(_ rest: String) -> String {
        guard let leadingSeparatorRegex else { return rest }
        return leadingSeparatorRegex.stringByReplacingMatches(
            in: rest,
            range: NSRange(rest.startIndex..., in: rest),
            withTemplate: ""
        )
    }

    /// «6 690,00» / «6,690.00» / «6690» -> «6690.00». nil, если не число.
    private static func normalizedPrice(_ raw: String) -> String? {
        var cleaned = String(raw.filter { $0.isNumber || $0 == "," || $0 == "." })
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(",") && cleaned.contains(".") {
            // Обе разделительные: запятая — разряды («6,690.00»).
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned) else { return nil }
        return String(format: "%.2f", value)
    }

    private static func currencyCode(for token: String?) -> String? {
        guard let token else { return nil }
        return currencyByToken[token.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    private static let currencyByToken: [String: String] = [
        "₽": "RUB", "руб": "RUB", "руб.": "RUB", "р.": "RUB", "rub": "RUB",
        "$": "USD", "usd": "USD",
        "€": "EUR", "eur": "EUR",
    ]

    // Ключи шапки. Короткие и неоднозначные («tg», «wa», «max») намеренно не берём:
    // с них начинаются наименования товаров («Max Mara: …»).
    private static let serviceKeys: Set<String> = [
        "итого", "сумма", "total",
        "имя", "клиент", "фио", "заказчик",
        "телефон", "тел", "phone",
        "способ связи", "связь", "contact",
        "доставка", "способ доставки", "delivery", "адрес", "адрес доставки",
        "комментарий", "коммент", "примечание", "comment",
        "telegram", "телеграм", "whatsapp", "ватсап", "viber", "вайбер",
        "instagram", "инстаграм", "avito", "авито",
        "email", "e-mail", "почта", "оплата",
    ]
}
