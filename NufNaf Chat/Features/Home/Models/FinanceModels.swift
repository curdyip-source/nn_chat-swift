import Foundation

/// «Финансы» в приложении (GET /finance/app/items): отгруженные позиции за период,
/// всё в валюте продажи — без пересчёта по курсу, как в вебе.
struct AppFinanceResponse: Decodable {
    let revenue: [AppFinanceTotal]
    let profit: [AppFinanceTotal]
    let itemsCount: Int
    let missingPurchaseCount: Int
    let items: [AppFinanceItem]

    enum CodingKeys: String, CodingKey {
        case revenue, profit, items
        case itemsCount = "items_count"
        case missingPurchaseCount = "missing_purchase_count"
    }
}

/// Сумма в одной валюте («12 500 $»); выручка/прибыль — список таких, по валютам.
struct AppFinanceTotal: Decodable, Hashable {
    let currency: String
    let amount: String
}

struct AppFinanceItem: Decodable, Identifiable, Hashable {
    let id: Int
    let orderID: Int
    /// День отгрузки (YYYY-MM-DD) — в той же шкале, что фильтр периода на сервере.
    let shippedDate: String?
    let establishmentName: String?
    let name: String
    let quantity: Int
    let price: String
    let currency: String
    /// Закупка за единицу в валюте продажи; nil — ещё не внесена.
    let purchasePrice: String?
    /// Снимок себестоимости из каталога — только подсказка в пустом поле.
    let suggestedPurchasePrice: String?
    let locked: Bool

    enum CodingKeys: String, CodingKey {
        case id = "order_item_id"
        case orderID = "order_id"
        case shippedDate = "shipped_date"
        case establishmentName = "establishment_name"
        case name, quantity, price, currency, locked
        case purchasePrice = "purchase_price"
        case suggestedPurchasePrice = "suggested_purchase_price"
    }
}

struct AppFinancePurchaseRequest: Encodable {
    let purchasePrice: String?

    enum CodingKeys: String, CodingKey {
        case purchasePrice = "purchase_price"
    }

    // purchase_price: null нужно отправить явно (очистка), а не пропустить ключ.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purchasePrice, forKey: .purchasePrice)
    }
}

struct AppFinanceLockRequest: Encodable {
    let locked: Bool
}
