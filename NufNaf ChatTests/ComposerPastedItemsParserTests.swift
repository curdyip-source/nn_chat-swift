//
//  ComposerPastedItemsParserTests.swift
//  NufNaf ChatTests
//
//  Разбор вставленного в композер списка позиций.
//

import Testing
@testable import NufNaf_Chat

struct ComposerPastedItemsParserTests {
    @Test func parsesNumberedListWithPricesAndTotals() {
        let items = ComposerPastedItemsParser.parse(
            """
            1. Kajal: Dahab 100ml 1 x 8224₽ = 8224₽
            2. Gucci: Flora Gorgeous Orchid 100ml tester 1 x 5619₽ = 5619₽
            3. hugo boss: Boss: Bottled edt 100ml tester 1 x 3161₽ = 3161₽
            4. Prada: Candy 80ml 1 x 6635₽ = 6635₽
            5. Montale: Arabians Tonka 100ml tester 1 x 5981₽ = 5981₽
            """
        )

        #expect(items.count == 5)
        #expect(items[0] == ComposerPastedItem(name: "Kajal: Dahab 100ml", quantity: 1, price: "8224.00", currencyCode: "RUB"))
        // Двоеточие внутри наименования не превращает строку в «ключ: значение».
        #expect(items[2].name == "hugo boss: Boss: Bottled edt 100ml tester")
        #expect(items[4] == ComposerPastedItem(name: "Montale: Arabians Tonka 100ml tester", quantity: 1, price: "5981.00", currencyCode: "RUB"))
    }

    @Test func keepsTrailingNumbersInNameAndReadsQuantity() {
        let items = ComposerPastedItemsParser.parse("Montale: Arabians Tonka 100ml 3 x 5 981,50 ₽ = 17 944,50₽")

        #expect(items.count == 1)
        #expect(items[0].name == "Montale: Arabians Tonka 100ml")
        #expect(items[0].quantity == 3)
        #expect(items[0].price == "5981.50")
    }

    @Test func acceptsListWithoutNumberingCurrencyAndTotal() {
        let items = ComposerPastedItemsParser.parse(
            """
            Prada: Candy 80ml 2 x 6635
            Dior: Sauvage 100ml 1 х 7 100$
            """
        )

        #expect(items.count == 2)
        #expect(items[0] == ComposerPastedItem(name: "Prada: Candy 80ml", quantity: 2, price: "6635.00", currencyCode: nil))
        // Кириллическая «х» — тоже знак умножения.
        #expect(items[1] == ComposerPastedItem(name: "Dior: Sauvage 100ml", quantity: 1, price: "7100.00", currencyCode: "USD"))
    }

    @Test func treatsPlainLineAsNameWithoutPrice() {
        let items = ComposerPastedItemsParser.parse(
            """
            1. Kajal: Dahab 100ml
            Max Mara: Le Parfum 90ml
            """
        )

        #expect(items.count == 2)
        #expect(items[0] == ComposerPastedItem(name: "Kajal: Dahab 100ml", quantity: 1, price: nil, currencyCode: nil))
        // Наименование, похожее на «ключ: значение», не должно теряться.
        #expect(items[1].name == "Max Mara: Le Parfum 90ml")
    }

    @Test func skipsHeaderAndFooterLinesOfSiteOrder() {
        let items = ComposerPastedItemsParser.parse(
            """
            Новый заказ! RETAIL web
            Имя: Степан

            Телефон: +79397236541
            Способ связи: Telegram
            Доставка: Яндекс Доставка
            Telegram: @fonik227

            1. Versace: Eros Flame 100ml 1 x 6690₽ = 6690₽

            Итого: 6690₽
            https://nufnaf.ru/unsubscribe
            """
        )

        #expect(items.count == 1)
        #expect(items[0] == ComposerPastedItem(name: "Versace: Eros Flame 100ml", quantity: 1, price: "6690.00", currencyCode: "RUB"))
    }

    @Test func parsesTableWithQuantityFirstAndPriceColumn() {
        let items = ComposerPastedItemsParser.parse(
            """
            1 шт\tГель для душа Amouage Guidance 360 ml\t64
            3 шт\tГель для душа Chanel Allure Homme port 200 ml\t75
            12 шт\tChanel Coco Mademoiselle, Eau De Parfum, 1,5 мл\t7
            40 шт\tCreed Aventus for Him, Eau De Parfum, 1,7 мл\t6
            5 шт\tDior Sauvage EDP 10 ml \t24
            1 шт\tThomas Kosmala № 4 Apres L'Amour, Eau De Parfum, 100 мл\t75
            5 шт\tYSL: Libre edp 10 ml (travel no box)\t17
            """
        )

        #expect(items.count == 7)
        #expect(items[0] == ComposerPastedItem(name: "Гель для душа Amouage Guidance 360 ml", quantity: 1, price: "64.00", currencyCode: nil))
        #expect(items[1].quantity == 3)
        // Числа внутри наименования («1,5 мл») ценой не считаются.
        #expect(items[2] == ComposerPastedItem(name: "Chanel Coco Mademoiselle, Eau De Parfum, 1,5 мл", quantity: 12, price: "7.00", currencyCode: nil))
        #expect(items[3].quantity == 40)
        // Пробел перед табом не отрывает цену.
        #expect(items[4] == ComposerPastedItem(name: "Dior Sauvage EDP 10 ml", quantity: 5, price: "24.00", currencyCode: nil))
        #expect(items[5].name == "Thomas Kosmala № 4 Apres L'Amour, Eau De Parfum, 100 мл")
        // Двоеточие в наименовании не делает строку «ключ: значение».
        #expect(items[6] == ComposerPastedItem(name: "YSL: Libre edp 10 ml (travel no box)", quantity: 5, price: "17.00", currencyCode: nil))
    }

    @Test func readsQuantityFirstLineWithoutTabsAndWithoutPrice() {
        let items = ComposerPastedItemsParser.parse(
            """
            2 шт Chanel Egoiste Platinum EDT 100 мл 143
            2 шт Chanel Fraiche, Eau De Toilette , 50 мл
            """
        )

        #expect(items.count == 2)
        // Табы потерялись при копировании — цену берём последним словом строки.
        #expect(items[0] == ComposerPastedItem(name: "Chanel Egoiste Platinum EDT 100 мл", quantity: 2, price: "143.00", currencyCode: nil))
        // Цены в строке нет — позиция уходит в корзину без цены.
        #expect(items[1] == ComposerPastedItem(name: "Chanel Fraiche, Eau De Toilette , 50 мл", quantity: 2, price: nil, currencyCode: nil))
    }

    @Test func parsesQuantityColumnWithoutUnitWord() {
        let items = ComposerPastedItemsParser.parse("2\tCreed Aventus EDP 100 ml\t287 $")

        #expect(items.count == 1)
        #expect(items[0] == ComposerPastedItem(name: "Creed Aventus EDP 100 ml", quantity: 2, price: "287.00", currencyCode: "USD"))
    }

    @Test func returnsNothingForEmptyText() {
        #expect(ComposerPastedItemsParser.parse("").isEmpty)
        #expect(ComposerPastedItemsParser.parse("   \n\n  ").isEmpty)
    }
}
