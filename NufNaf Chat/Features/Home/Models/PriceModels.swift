import Foundation

/// Поставщик с актуальным прайсом (из nn_vla). CL добавляется в список источников
/// на клиенте отдельно.
struct PriceSupplier: Decodable, Identifiable, Hashable {
    let email: String
    let date: String

    var id: String { email }
}

struct PriceSuppliersResponse: Decodable {
    let items: [PriceSupplier]
}

/// Строка живого поиска по прайс-листам. Цена приходит строкой ("12.00"),
/// id дублируется между источниками — для идентичности используем rowID.
struct PriceSearchResult: Decodable, Hashable {
    let id: Int
    let code: String?
    let name: String
    let price: String?
    let source: String       // "CL" либо email поставщика
    let supplier: String?
    let priceDate: String?

    enum CodingKeys: String, CodingKey {
        case id, code, name, price, source, supplier
        case priceDate = "price_date"
    }

    var rowID: String { "\(source)-\(id)" }
    var isCL: Bool { source == "CL" }
}

struct PriceSearchResponse: Decodable {
    let count: Int
    let results: [PriceSearchResult]
}
