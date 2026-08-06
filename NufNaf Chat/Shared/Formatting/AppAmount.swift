//
//  AppAmount.swift
//  NufNaf Chat
//
//  Единый формат денежных сумм в приложении: тысячи разделяем пробелом
//  (17 308.00 вместо 17308.00), дробная часть — через точку, как приходит с API.
//  Разделитель — неразрывный пробел, чтобы число не переносилось по строкам.
//

import Foundation

enum AppAmount {
    /// Неразрывный пробел: визуально обычный пробел, но число не рвётся переносом.
    static let groupingSeparator = "\u{00A0}"

    /// Сумма-строка из API («17308.00») → «17 308.00».
    ///
    /// Дробная часть, её разделитель и знак остаются как пришли: форматируем только
    /// разряды целой части. Всё, что не похоже на число, возвращаем без изменений.
    static func grouped(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return raw }

        var sign = ""
        var body = Substring(value)
        if let first = body.first, first == "-" || first == "+" {
            sign = String(first)
            body = body.dropFirst()
        }

        let separatorIndex = body.firstIndex(where: { $0 == "." || $0 == "," })
        let integerPart = separatorIndex.map { String(body[body.startIndex..<$0]) } ?? String(body)
        let fractionPart = separatorIndex.map { String(body[$0...]) } ?? ""

        guard !integerPart.isEmpty, integerPart.allSatisfy(\.isNumber) else { return raw }
        guard integerPart.count > 3 else { return sign + integerPart + fractionPart }

        return sign + group(integerPart) + fractionPart
    }

    /// Число → «17 308» / «17 308.50» (нули в конце дробной части не показываем).
    static func grouped(_ value: Double) -> String {
        grouped(formatter.string(from: NSNumber(value: value)) ?? String(value))
    }

    /// Decimal → «17 308.50». Используется для сумм, посчитанных на клиенте.
    static func grouped(_ value: Decimal) -> String {
        grouped(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)")
    }

    /// Сумма с валютой без пробела перед знаком: «17 308.00₽» (как в карточках).
    static func groupedWithCurrency(_ raw: String, _ currency: String) -> String {
        "\(grouped(raw))\(currency)"
    }

    private static func group(_ digits: String) -> String {
        var result = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                result.append(contentsOf: groupingSeparator.reversed())
            }
            result.append(character)
        }
        return String(result.reversed())
    }

    /// Точка как десятичный разделитель и без группировки — разряды расставляем сами
    /// (locale здесь только чтобы формат не зависел от настроек устройства).
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
