//
//  AppAmountTests.swift
//  NufNaf ChatTests
//
//  Формат сумм: разряды тысяч разделяются пробелом (17 308.00).
//

import Foundation
import Testing
@testable import NufNaf_Chat

struct AppAmountTests {
    private let space = AppAmount.groupingSeparator

    @Test func groupsThousandsInApiString() {
        #expect(AppAmount.grouped("17308.00") == "17\(space)308.00")
        #expect(AppAmount.grouped("6690") == "6\(space)690")
        #expect(AppAmount.grouped("1234567.89") == "1\(space)234\(space)567.89")
        // До тысячи разряды не разделяем.
        #expect(AppAmount.grouped("999.00") == "999.00")
    }

    @Test func keepsFractionSeparatorAndSignAsIs() {
        // Дробная часть приходит как есть — точкой или запятой, её не трогаем.
        #expect(AppAmount.grouped("17308,50") == "17\(space)308,50")
        #expect(AppAmount.grouped("-17308.00") == "-17\(space)308.00")
    }

    @Test func leavesNonNumericValuesUntouched() {
        #expect(AppAmount.grouped("") == "")
        #expect(AppAmount.grouped("нет цены") == "нет цены")
        #expect(AppAmount.grouped("12 шт.") == "12 шт.")
    }

    @Test func formatsNumbersWithoutTrailingZeros() {
        #expect(AppAmount.grouped(17308.0) == "17\(space)308")
        #expect(AppAmount.grouped(17308.5) == "17\(space)308.5")
        #expect(AppAmount.grouped(Decimal(string: "29801.50")!) == "29\(space)801.5")
        #expect(AppAmount.grouped(999.0) == "999")
    }

    @Test func doesNotGroupAlreadyGroupedValue() {
        // Повторное форматирование не должно ломать строку (пробел — не цифра).
        let once = AppAmount.grouped("17308.00")
        #expect(AppAmount.grouped(once) == once)
    }
}
