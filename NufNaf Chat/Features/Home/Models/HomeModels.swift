//
//  HomeModels.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Foundation

struct HomeItemEnvelope<Item: Decodable>: Decodable {
    let item: Item
}

struct HomeReferenceDataResponse: Decodable {
    let establishments: [HomeEstablishment]
    let orderMethods: [HomeOrderMethod]
    let salesChannels: [HomeOrderSalesChannel]
    let statuses: [HomeStatus]
    let currencies: [HomeCurrency]
    // Минимальный допустимый билд iOS (гейт форс-апдейта). 0 = выключен.
    let minSupportedIosBuild: Int

    enum CodingKeys: String, CodingKey {
        case establishments
        case orderMethods = "order_methods"
        case salesChannels = "sales_channels"
        case statuses
        case currencies
        case minSupportedIosBuild = "min_supported_ios_build"
    }

    init(establishments: [HomeEstablishment], orderMethods: [HomeOrderMethod], salesChannels: [HomeOrderSalesChannel] = [], statuses: [HomeStatus], currencies: [HomeCurrency], minSupportedIosBuild: Int = 0) {
        self.establishments = establishments
        self.orderMethods = orderMethods
        self.salesChannels = salesChannels
        self.statuses = statuses
        self.currencies = currencies
        self.minSupportedIosBuild = minSupportedIosBuild
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        establishments = try container.decode([HomeEstablishment].self, forKey: .establishments)
        orderMethods = try container.decode([HomeOrderMethod].self, forKey: .orderMethods)
        // sales_channels может отсутствовать (старый бэкенд/кэш) — не роняем весь справочник.
        salesChannels = try container.decodeIfPresent([HomeOrderSalesChannel].self, forKey: .salesChannels) ?? []
        statuses = try container.decode([HomeStatus].self, forKey: .statuses)
        currencies = try container.decode([HomeCurrency].self, forKey: .currencies)
        minSupportedIosBuild = try container.decodeIfPresent(Int.self, forKey: .minSupportedIosBuild) ?? 0
    }
}

struct HomeOrderSalesChannel: Codable, Identifiable, Hashable {
    let id: Int
    let orderSalesChannelName: String

    enum CodingKeys: String, CodingKey {
        case id = "order_sales_channel_id"
        case orderSalesChannelName = "order_sales_channel_name"
    }
}

struct HomeEstablishment: Codable, Identifiable, Hashable {
    let id: Int
    let establishmentName: String

    enum CodingKeys: String, CodingKey {
        case id = "establishment_id"
        case establishmentName = "establishment_name"
    }
}

struct HomeOrderMethod: Codable, Identifiable, Hashable {
    let id: Int
    let orderMethodName: String
    let orderMethodSubMethods: [String]

    enum CodingKeys: String, CodingKey {
        case id = "order_method_id"
        case orderMethodName = "order_method_name"
        case orderMethodSubMethods = "order_method_sub_methods"
    }
}

struct HomeStatus: Codable, Identifiable, Hashable {
    let id: Int
    let statusType: String
    let statusStatus: String
    let statusColor: String?

    enum CodingKeys: String, CodingKey {
        case id = "status_id"
        case statusType = "status_type"
        case statusStatus = "status_status"
        case statusColor = "status_color"
    }
}

struct HomeCurrency: Codable, Identifiable, Hashable {
    let id: Int
    let currencyName: String
    let currencySign: String?

    enum CodingKeys: String, CodingKey {
        case id = "currency_id"
        case currencyName = "currency_name"
        case currencySign = "currency_sign"
    }
}

struct HomeProductResponse: Decodable {
    let items: [HomeProduct]
}

struct HomeContactResponse: Decodable {
    let items: [HomeContact]
}

struct HomeContact: Codable, Identifiable, Hashable {
    let id: Int
    let contactType: String
    let contactName: String
    let contactInfo: String?
    let contactEstablishmentID: Int?
    let contactEstablishmentName: String?
    let contactOrderMethodID: Int?
    let contactOrderMethodName: String?
    let contactOrderSubMethod: String?
    let contactContactMethod: String?
    let contactSalesChannel: String?

    enum CodingKeys: String, CodingKey {
        case id = "contact_id"
        case contactType = "contact_type"
        case contactName = "contact_name"
        case contactInfo = "contact_info"
        case contactEstablishmentID = "contact_establishment_id"
        case contactEstablishmentName = "contact_establishment_name"
        case contactOrderMethodID = "contact_order_method_id"
        case contactOrderMethodName = "contact_order_method_name"
        case contactOrderSubMethod = "contact_order_sub_method"
        case contactContactMethod = "contact_contact_method"
        case contactSalesChannel = "contact_sales_channel"
    }
}

struct HomeProduct: Codable, Identifiable, Hashable {
    let id: Int
    let productArticle: String
    let productName: String
    let productCostUSD: String

    enum CodingKeys: String, CodingKey {
        case id = "product_id"
        case productArticle = "product_article"
        case productName = "product_name"
        case productCostUSD = "product_cost_usd"
    }
}

struct HomeProductCreateRequest: Encodable {
    let productArticle: String
    let productName: String
    let productCostUSD: String

    enum CodingKeys: String, CodingKey {
        case productArticle = "product_article"
        case productName = "product_name"
        case productCostUSD = "product_cost_usd"
    }
}

struct HomeMessageResponse: Decodable {
    let items: [HomeMessage]
}

enum HomeMessageDeliveryState: Hashable {
    case sent
    case pending
    case failed
}

struct HomeMessage: Codable, Identifiable, Hashable {
    let id: Int
    let messageType: String
    let messageText: String?
    let messageOwnerUserID: Int
    let messageOwnerUserLogin: String?
    let messageOwnerFirstName: String?
    let messageOwnerSecondName: String?
    let messageOwnerProfilePhoto: String?
    let messageOrderID: Int?
    let messageInventoryID: Int?
    let messageProductRegistrationID: Int?
    let messageStatus: String?
    let messageStatusColor: String?
    let messageCreatedAt: String?
    let attachments: [HomeMessageAttachment]
    let order: HomeOrder?
    let inventory: HomeInventory?
    let productRegistration: HomeProductRegistration?
    var deliveryState: HomeMessageDeliveryState = .sent

    enum CodingKeys: String, CodingKey {
        case id = "message_id"
        case messageType = "message_type"
        case messageText = "message_text"
        case messageOwnerUserID = "message_owner_user_id"
        case messageOwnerUserLogin = "message_owner_user_login"
        case messageOwnerFirstName = "message_owner_first_name"
        case messageOwnerSecondName = "message_owner_second_name"
        case messageOwnerProfilePhoto = "message_owner_profile_photo"
        case messageOrderID = "message_order_id"
        case messageInventoryID = "message_inventory_id"
        case messageProductRegistrationID = "message_product_registration_id"
        case messageStatus = "message_status"
        case messageStatusColor = "message_status_color"
        case messageCreatedAt = "message_created_at"
        case attachments
        case order
        case inventory
        case productRegistration = "product_registration"
    }

    var documentKind: String? {
        if messageOrderID != nil { return "order" }
        if messageInventoryID != nil { return "inventory" }
        if messageProductRegistrationID != nil { return "product_registration" }
        return nil
    }

    var documentID: Int? {
        messageOrderID ?? messageInventoryID ?? messageProductRegistrationID
    }

    /// Stable, unique reference title for a document message (order/inventory/registration).
    /// Used as the reply snippet so tapping a reply quote resolves to the exact document
    /// instead of matching on non-unique text and falling back to the latest one.
    var documentReferenceTitle: String? {
        guard let kind = documentKind, let id = documentID else { return nil }
        switch kind {
        case "order": return "Заказ №\(id)"
        case "inventory": return "Инвентаризация №\(id)"
        case "product_registration": return "Приемка №\(id)"
        default: return nil
        }
    }

    var displayName: String {
        let fullName = [messageOwnerSecondName, messageOwnerFirstName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return messageOwnerUserLogin ?? "Пользователь"
    }

    var parsedCreatedAt: Date? {
        HomeMessageDateParser.parse(messageCreatedAt)
    }

    var canRetryDelivery: Bool {
        deliveryState == .failed && (documentKind != nil || messageType == "message" || !attachments.isEmpty)
    }

    var isLocalOnly: Bool {
        id < 0
    }
}

extension HomeMessage {
    static func makeLocalTextMessage(id: Int, text: String, user: AuthUser, deliveryState: HomeMessageDeliveryState) -> HomeMessage {
        HomeMessage(
            id: id,
            messageType: "message",
            messageText: text,
            messageOwnerUserID: user.userID,
            messageOwnerUserLogin: user.userLogin,
            messageOwnerFirstName: user.userFirstName,
            messageOwnerSecondName: user.userSecondName,
            messageOwnerProfilePhoto: user.userProfilePhoto,
            messageOrderID: nil,
            messageInventoryID: nil,
            messageProductRegistrationID: nil,
            messageStatus: nil,
            messageStatusColor: nil,
            messageCreatedAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachments: [],
            order: nil,
            inventory: nil,
            productRegistration: nil,
            deliveryState: deliveryState
        )
    }

    static func makeLocalAttachmentMessage(id: Int, attachment: HomeMessageAttachment, user: AuthUser, deliveryState: HomeMessageDeliveryState) -> HomeMessage {
        HomeMessage(
            id: id,
            messageType: "file",
            messageText: nil,
            messageOwnerUserID: user.userID,
            messageOwnerUserLogin: user.userLogin,
            messageOwnerFirstName: user.userFirstName,
            messageOwnerSecondName: user.userSecondName,
            messageOwnerProfilePhoto: user.userProfilePhoto,
            messageOrderID: nil,
            messageInventoryID: nil,
            messageProductRegistrationID: nil,
            messageStatus: nil,
            messageStatusColor: nil,
            messageCreatedAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachments: [attachment],
            order: nil,
            inventory: nil,
            productRegistration: nil,
            deliveryState: deliveryState
        )
    }
}

extension ISO8601DateFormatter {
    static let localMessageTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct HomeMessageAttachment: Codable, Hashable, Identifiable {
    let attachmentID: Int
    let attachmentKind: String
    let attachmentOriginalFilename: String
    let attachmentMimeType: String
    let attachmentStorageKey: String
    let attachmentSizeBytes: Int?
    let attachmentCreatedAt: String?
    var attachmentLocalFilePath: String? = nil

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
        case attachmentKind = "attachment_kind"
        case attachmentOriginalFilename = "attachment_original_filename"
        case attachmentMimeType = "attachment_mime_type"
        case attachmentStorageKey = "attachment_storage_key"
        case attachmentSizeBytes = "attachment_size_bytes"
        case attachmentCreatedAt = "attachment_created_at"
    }

    var isPhoto: Bool {
        attachmentKind == "photo"
    }

    var id: Int { attachmentID }

    var localFileURL: URL? {
        guard let attachmentLocalFilePath, !attachmentLocalFilePath.isEmpty else { return nil }
        return URL(fileURLWithPath: attachmentLocalFilePath)
    }

    var mediaURL: URL? {
        localFileURL ?? AppConfig.messageAttachmentURL(for: attachmentID)
    }
}

extension HomeMessageAttachment {
    static func makeLocal(id: Int, kind: String, filename: String, mimeType: String, sizeBytes: Int, localFileURL: URL) -> HomeMessageAttachment {
        HomeMessageAttachment(
            attachmentID: id,
            attachmentKind: kind,
            attachmentOriginalFilename: filename,
            attachmentMimeType: mimeType,
            attachmentStorageKey: "local-\(UUID().uuidString)",
            attachmentSizeBytes: sizeBytes,
            attachmentCreatedAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachmentLocalFilePath: localFileURL.path
        )
    }
}

struct HomeUploadedMessageAttachment: Decodable, Hashable {
    let attachmentKind: String
    let attachmentOriginalFilename: String
    let attachmentMimeType: String
    let attachmentStorageKey: String
    let attachmentSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case attachmentKind = "attachment_kind"
        case attachmentOriginalFilename = "attachment_original_filename"
        case attachmentMimeType = "attachment_mime_type"
        case attachmentStorageKey = "attachment_storage_key"
        case attachmentSizeBytes = "attachment_size_bytes"
    }
}

struct HomeMessageAttachmentCreateRequest: Encodable, Hashable {
    let attachmentKind: String
    let attachmentOriginalFilename: String
    let attachmentMimeType: String
    let attachmentStorageKey: String
    let attachmentSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case attachmentKind = "attachment_kind"
        case attachmentOriginalFilename = "attachment_original_filename"
        case attachmentMimeType = "attachment_mime_type"
        case attachmentStorageKey = "attachment_storage_key"
        case attachmentSizeBytes = "attachment_size_bytes"
    }
}

struct HomeProfileUpdateRequest: Encodable {
    var userFirstName: String?
    var userSecondName: String?
    var userProfilePhoto: String?
    var userAge: Int?
    var userAddress: String?

    enum CodingKeys: String, CodingKey {
        case userFirstName = "user_first_name"
        case userSecondName = "user_second_name"
        case userProfilePhoto = "user_profile_photo"
        case userAge = "user_age"
        case userAddress = "user_address"
    }
}

enum HomeChatFilterKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case message
    case order
    case inventory
    case productRegistration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .message:
            return "Сообщения"
        case .order:
            return "Заказы"
        case .inventory:
            return "Инвентаризации"
        case .productRegistration:
            return "Приемки"
        }
    }
}

/// Экраны приложения в порядке листания слева направо: Прайс → Чат → СРМ → Задачи.
/// Стартовый экран при запуске — Чат (см. HomeChatFilterState.default).
enum HomeDisplayMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case price
    case chat
    case crm
    case todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Чат"
        case .crm:
            return "CRM"
        case .price:
            return "Прайс"
        case .todo:
            return "Задачи"
        }
    }
}

struct HomeChatFilterState: Codable, Equatable {
    var displayMode: HomeDisplayMode
    var year: Int
    var months: Set<Int>
    var kinds: Set<HomeChatFilterKind>
    var hideCompleted: Bool
    var hideCancelled: Bool
    var orderMethodIDs: Set<Int>
    var establishmentIDs: Set<Int>
    var statusIDs: Set<Int>

    static func `default`(currentYear: Int = Calendar.current.component(.year, from: Date())) -> HomeChatFilterState {
        HomeChatFilterState(
            displayMode: .chat,
            year: currentYear,
            months: [],
            kinds: [],
            hideCompleted: true,
            hideCancelled: true,
            orderMethodIDs: [],
            establishmentIDs: [],
            statusIDs: []
        )
    }

    func resettingCriteria() -> HomeChatFilterState {
        HomeChatFilterState(
            displayMode: displayMode,
            year: Calendar.current.component(.year, from: Date()),
            months: [],
            kinds: [],
            hideCompleted: true,
            hideCancelled: true,
            orderMethodIDs: [],
            establishmentIDs: [],
            statusIDs: []
        )
    }

    /// true, если задан хоть один критерий отбора, отличающийся от дефолта (год !=
    /// текущего, выбраны месяцы/виды/методы/точки/статусы, либо «скрыть выполненные/
    /// отмененные» переключены из состояния по умолчанию). Переключение режима
    /// чат/CRM критерием НЕ считается — оно сохраняется в resettingCriteria().
    var hasActiveCriteria: Bool {
        self != resettingCriteria()
    }

    enum CodingKeys: String, CodingKey {
        case displayMode
        case year
        case months
        case kinds
        case hideCompleted
        case hideCancelled
        case orderMethodIDs
        case establishmentIDs
        case statusIDs
    }

    init(
        displayMode: HomeDisplayMode,
        year: Int,
        months: Set<Int>,
        kinds: Set<HomeChatFilterKind>,
        hideCompleted: Bool,
        hideCancelled: Bool,
        orderMethodIDs: Set<Int>,
        establishmentIDs: Set<Int>,
        statusIDs: Set<Int>
    ) {
        self.displayMode = displayMode
        self.year = year
        self.months = months
        self.kinds = kinds
        self.hideCompleted = hideCompleted
        self.hideCancelled = hideCancelled
        self.orderMethodIDs = orderMethodIDs
        self.establishmentIDs = establishmentIDs
        self.statusIDs = statusIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayMode = try container.decodeIfPresent(HomeDisplayMode.self, forKey: .displayMode) ?? .chat
        year = try container.decode(Int.self, forKey: .year)
        months = try container.decodeIfPresent(Set<Int>.self, forKey: .months) ?? []
        kinds = try container.decodeIfPresent(Set<HomeChatFilterKind>.self, forKey: .kinds) ?? []
        hideCompleted = try container.decodeIfPresent(Bool.self, forKey: .hideCompleted) ?? true
        hideCancelled = try container.decodeIfPresent(Bool.self, forKey: .hideCancelled) ?? true
        orderMethodIDs = try container.decodeIfPresent(Set<Int>.self, forKey: .orderMethodIDs) ?? []
        establishmentIDs = try container.decodeIfPresent(Set<Int>.self, forKey: .establishmentIDs) ?? []
        statusIDs = try container.decodeIfPresent(Set<Int>.self, forKey: .statusIDs) ?? []
    }
}

struct HomeReplyFragment: Equatable {
    let author: String
    let message: String
    let body: String?
}

enum HomeComposerKind: String, Identifiable {
    case order
    case inventory
    case productRegistration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .order:
            return "Новый заказ"
        case .inventory:
            return "Новая инвентаризация"
        case .productRegistration:
            return "Новая приемка"
        }
    }
}

struct HomeComposerItemDraft: Identifiable, Hashable {
    let id: UUID
    var productID: Int?
    var article: String
    var name: String
    var quantity: Int
    var price: String
    var statusID: Int?
    var currencyID: Int?

    init(id: UUID = UUID(), productID: Int? = nil, article: String = "", name: String = "", quantity: Int = 1, price: String = "0.00", statusID: Int? = nil, currencyID: Int? = nil) {
        self.id = id
        self.productID = productID
        self.article = article
        self.name = name
        self.quantity = quantity
        self.price = price
        self.statusID = statusID
        self.currencyID = currencyID
    }

    init(item: HomeOrderItem) {
        self.id = UUID()
        self.productID = item.orderItemProductID
        self.article = item.orderItemArticle ?? ""
        self.name = item.orderItemName
        self.quantity = item.orderItemQuantity
        self.price = item.orderItemPrice
        self.statusID = item.orderItemStatusID
        self.currencyID = item.orderItemCurrencyID
    }
}

struct HomeMessageCreateRequest: Encodable {
    let messageType: String
    let messageText: String?
    let attachments: [HomeMessageAttachmentCreateRequest]
    var mentionedUserIDs: [Int] = []

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case messageText = "message_text"
        case attachments
        case mentionedUserIDs = "mentioned_user_ids"
    }
}

struct ChatParticipant: Codable, Identifiable, Hashable {
    let id: Int
    let userLogin: String
    let userFirstName: String
    let userSecondName: String
    let userProfilePhoto: String?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case userLogin = "user_login"
        case userFirstName = "user_first_name"
        case userSecondName = "user_second_name"
        case userProfilePhoto = "user_profile_photo"
    }

    var displayName: String {
        let fullName = [userSecondName, userFirstName]
            .compactMap { $0.isEmpty ? nil : $0 }
            .joined(separator: " ")
        return fullName.isEmpty ? userLogin : fullName
    }
}

struct ChatParticipantsResponse: Decodable {
    let items: [ChatParticipant]
}

struct HomeMessageUpdateRequest: Encodable {
    let messageText: String

    enum CodingKeys: String, CodingKey {
        case messageText = "message_text"
    }
}

struct HomeOrderCdekRequest: Encodable {
    let recipientName: String?
    let recipientPhone: String?
    let cityCode: Int?
    let cityName: String?
    let deliveryMode: String?
    let pvzCode: String?
    let pvzAddress: String?
    let deliveryAddress: String?
    enum CodingKeys: String, CodingKey {
        case recipientName = "recipient_name"
        case recipientPhone = "recipient_phone"
        case cityCode = "city_code"
        case cityName = "city_name"
        case deliveryMode = "delivery_mode"
        case pvzCode = "pvz_code"
        case pvzAddress = "pvz_address"
        case deliveryAddress = "delivery_address"
    }
}

struct HomeOrderCreateRequest: Encodable {
    let orderEstablishmentID: Int
    let orderMethodID: Int?
    let orderSubMethod: String?
    let orderContactMethod: String?
    let orderSalesChannel: String?
    let orderCustomer: String
    let orderInfo: String
    let orderStatusID: Int?
    let saveContact: Bool
    let cdek: HomeOrderCdekRequest?
    let items: [HomeOrderItemCreateRequest]

    enum CodingKeys: String, CodingKey {
        case orderEstablishmentID = "order_establishment_id"
        case orderMethodID = "order_method_id"
        case orderSubMethod = "order_sub_method"
        case orderContactMethod = "order_contact_method"
        case orderSalesChannel = "order_sales_channel"
        case orderCustomer = "order_customer"
        case orderInfo = "order_info"
        case orderStatusID = "order_status_id"
        case saveContact = "save_contact"
        case cdek
        case items
    }
}

struct HomeOrder: Codable, Identifiable, Hashable {
    let id: Int
    let orderEstablishmentID: Int
    let orderEstablishmentName: String?
    // Способ заказа может быть не выбран: заказы с сайта приходят без него.
    let orderMethodID: Int?
    let orderMethodName: String?
    let orderSubMethod: String?
    let orderContactMethod: String?
    let orderSalesChannel: String?
    let orderCustomer: String
    let orderInfo: String
    let orderStatusID: Int
    let orderStatus: String?
    let orderStatusColor: String?
    let orderCreatedAt: String?
    let orderOwnerUserLogin: String?
    let orderOwnerFirstName: String?
    let orderOwnerSecondName: String?
    // Оплата: отметка с кнопки «Оплатить» в карточке заказа. Поля опциональные —
    // в кэше сообщений могут лежать карточки, снятые до появления оплаты.
    let orderPaid: Bool?
    let orderPaidAt: String?
    let orderPaidByUserLogin: String?
    let orderPaidByFirstName: String?
    let orderPaidBySecondName: String?
    let items: [HomeOrderItem]
    let comments: [HomeOrderComment]
    let cdek: HomeOrderCdek?

    enum CodingKeys: String, CodingKey {
        case id = "order_id"
        case orderEstablishmentID = "order_establishment_id"
        case orderEstablishmentName = "order_establishment_name"
        case orderMethodID = "order_method_id"
        case orderMethodName = "order_method_name"
        case orderSubMethod = "order_sub_method"
        case orderContactMethod = "order_contact_method"
        case orderSalesChannel = "order_sales_channel"
        case orderCustomer = "order_customer"
        case orderInfo = "order_info"
        case orderStatusID = "order_status_id"
        case orderStatus = "order_status"
        case orderStatusColor = "order_status_color"
        case orderCreatedAt = "order_created_at"
        case orderOwnerUserLogin = "order_owner_user_login"
        case orderOwnerFirstName = "order_owner_first_name"
        case orderOwnerSecondName = "order_owner_second_name"
        case orderPaid = "order_paid"
        case orderPaidAt = "order_paid_at"
        case orderPaidByUserLogin = "order_paid_by_user_login"
        case orderPaidByFirstName = "order_paid_by_first_name"
        case orderPaidBySecondName = "order_paid_by_second_name"
        case items
        case comments
        case cdek
    }

    /// Заказ отмечен оплаченным.
    var isPaid: Bool { orderPaid ?? false }

    /// Тексты закреплённых сообщений чата заказа — в порядке отправки, для карточки
    /// заказа в списках СРМ. Без автора и вложений: в карточке нужен только текст.
    var pinnedCommentTexts: [String] {
        comments
            .filter(\.isPinned)
            .sorted { $0.id < $1.id }
            .map(\.visibleText)
            .filter { !$0.isEmpty }
    }

    /// Кто отметил оплату: ФИО (Фамилия Имя), иначе логин.
    var orderPaidByDisplayName: String? {
        let fullName = [orderPaidBySecondName, orderPaidByFirstName]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        if let login = orderPaidByUserLogin, !login.isEmpty { return login }
        return nil
    }

    /// ФИО создателя заказа (Фамилия Имя), иначе логин. Для строки «Кем создана».
    var orderOwnerDisplayName: String? {
        let fullName = [orderOwnerSecondName, orderOwnerFirstName]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        if let login = orderOwnerUserLogin, !login.isEmpty { return login }
        return nil
    }
}

// MARK: - СДЭК (доставка)

/// Блок cdek у заказа (и ответ статуса накладной). Отдаётся бэкендом в serialize_order.
struct HomeOrderCdek: Codable, Hashable {
    let hasWaybill: Bool
    let uuid: String?
    let trackNumber: String?
    let status: String?
    let statusUpdatedAt: String?
    let recipientName: String?
    let recipientPhone: String?
    let cityCode: Int?
    let cityName: String?
    let deliveryMode: String?
    let pvzCode: String?
    let pvzAddress: String?
    let deliveryAddress: String?

    enum CodingKeys: String, CodingKey {
        case hasWaybill = "has_waybill"
        case uuid
        case trackNumber = "track_number"
        case status
        case statusUpdatedAt = "status_updated_at"
        case recipientName = "recipient_name"
        case recipientPhone = "recipient_phone"
        case cityCode = "city_code"
        case cityName = "city_name"
        case deliveryMode = "delivery_mode"
        case pvzCode = "pvz_code"
        case pvzAddress = "pvz_address"
        case deliveryAddress = "delivery_address"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasWaybill = (try? c.decode(Bool.self, forKey: .hasWaybill)) ?? false
        uuid = try? c.decode(String.self, forKey: .uuid)
        trackNumber = try? c.decode(String.self, forKey: .trackNumber)
        status = try? c.decode(String.self, forKey: .status)
        statusUpdatedAt = try? c.decode(String.self, forKey: .statusUpdatedAt)
        recipientName = try? c.decode(String.self, forKey: .recipientName)
        recipientPhone = try? c.decode(String.self, forKey: .recipientPhone)
        cityCode = try? c.decode(Int.self, forKey: .cityCode)
        cityName = try? c.decode(String.self, forKey: .cityName)
        deliveryMode = try? c.decode(String.self, forKey: .deliveryMode)
        pvzCode = try? c.decode(String.self, forKey: .pvzCode)
        pvzAddress = try? c.decode(String.self, forKey: .pvzAddress)
        deliveryAddress = try? c.decode(String.self, forKey: .deliveryAddress)
    }
}

struct CdekCity: Codable, Hashable, Identifiable {
    let code: Int
    let fullName: String?
    let cityUuid: String?
    var id: Int { code }
    enum CodingKeys: String, CodingKey {
        case code
        case fullName = "full_name"
        case cityUuid = "city_uuid"
    }
}

struct CdekPvz: Codable, Hashable, Identifiable {
    let code: String
    let name: String?
    let address: String?
    let workTime: String?
    let type: String?
    var id: String { code }
    enum CodingKeys: String, CodingKey {
        case code, name, address, type
        case workTime = "work_time"
    }
}

struct CdekTariff: Codable, Hashable, Identifiable {
    let tariffCode: Int
    let tariffName: String?
    let deliverySum: Double?
    let periodMin: Int?
    let periodMax: Int?
    var id: Int { tariffCode }
    enum CodingKeys: String, CodingKey {
        case tariffCode = "tariff_code"
        case tariffName = "tariff_name"
        case deliverySum = "delivery_sum"
        case periodMin = "period_min"
        case periodMax = "period_max"
    }
}

struct CdekPrefill: Codable, Hashable {
    let recipientName: String?
    let recipientPhone: String?
    let cityCode: Int?
    let cityName: String?
    let deliveryMode: String?
    let pvzCode: String?
    let pvzAddress: String?
    let deliveryAddress: String?
    enum CodingKeys: String, CodingKey {
        case recipientName = "recipient_name"
        case recipientPhone = "recipient_phone"
        case cityCode = "city_code"
        case cityName = "city_name"
        case deliveryMode = "delivery_mode"
        case pvzCode = "pvz_code"
        case pvzAddress = "pvz_address"
        case deliveryAddress = "delivery_address"
    }
}

struct CdekPackageRequest: Encodable {
    var weight: Int = 500
    var length: Int = 20
    var width: Int = 15
    var height: Int = 10
}

struct CdekWaybillCreateRequest: Encodable {
    let tariffCode: Int
    let recipientName: String
    let recipientPhone: String
    let fromCityCode: Int?
    let fromCityName: String?
    let shipmentPoint: String?
    let shipmentPointAddress: String?
    let cityCode: Int
    let cityName: String?
    let deliveryMode: String        // pvz | door
    let pvzCode: String?
    let pvzAddress: String?
    let deliveryAddress: String?
    let package: CdekPackageRequest
    let comment: String?
    let declaredValue: Double
    let insurance: Bool
    let sms: Bool
    let codAmount: Double
    let deliveryPaidByRecipient: Bool
    let deliveryCost: Double

    enum CodingKeys: String, CodingKey {
        case tariffCode = "tariff_code"
        case recipientName = "recipient_name"
        case recipientPhone = "recipient_phone"
        case fromCityCode = "from_city_code"
        case fromCityName = "from_city_name"
        case shipmentPoint = "shipment_point"
        case shipmentPointAddress = "shipment_point_address"
        case cityCode = "city_code"
        case cityName = "city_name"
        case deliveryMode = "delivery_mode"
        case pvzCode = "pvz_code"
        case pvzAddress = "pvz_address"
        case deliveryAddress = "delivery_address"
        case package
        case comment
        case declaredValue = "declared_value"
        case insurance
        case sms
        case codAmount = "cod_amount"
        case deliveryPaidByRecipient = "delivery_paid_by_recipient"
        case deliveryCost = "delivery_cost"
    }
}

struct CdekCitiesResponse: Decodable { let items: [CdekCity] }
struct CdekPvzResponse: Decodable { let items: [CdekPvz] }
struct CdekTariffsResponse: Decodable { let items: [CdekTariff] }

/// Дефолт отправителя (последний использованный ПВЗ сдачи + город) — /cdek/defaults.
struct CdekOriginDefault: Decodable {
    let fromCityCode: Int?
    let fromCityName: String?
    let shipmentPoint: String?
    let shipmentPointAddress: String?

    enum CodingKeys: String, CodingKey {
        case fromCityCode = "from_city_code"
        case fromCityName = "from_city_name"
        case shipmentPoint = "shipment_point"
        case shipmentPointAddress = "shipment_point_address"
    }
}

struct HomeOrderComment: Codable, Identifiable, Hashable {
    let id: Int
    let orderID: Int
    let text: String?
    let ownerUserID: Int
    let ownerUserLogin: String?
    let ownerFirstName: String?
    let ownerSecondName: String?
    let ownerProfilePhoto: String?
    let createdAt: String?
    let attachments: [HomeOrderCommentAttachment]
    // Опционально — как order_paid у заказа: закешированные payload'ы старых версий поля
    // не содержат, а обязательный Bool сломал бы им декодирование.
    var pinned: Bool? = nil
    var deliveryState: HomeMessageDeliveryState = .sent

    enum CodingKeys: String, CodingKey {
        case id = "order_comment_id"
        case orderID = "order_comment_order_id"
        case text = "order_comment_text"
        case ownerUserID = "order_comment_owner_user_id"
        case ownerUserLogin = "order_comment_owner_user_login"
        case ownerFirstName = "order_comment_owner_first_name"
        case ownerSecondName = "order_comment_owner_second_name"
        case ownerProfilePhoto = "order_comment_owner_profile_photo"
        case createdAt = "order_comment_created_at"
        case pinned = "order_comment_is_pinned"
        case attachments
    }

    /// Закреплённое сообщение: его текст выводится в карточке заказа в списках СРМ.
    var isPinned: Bool { pinned ?? false }

    var displayName: String {
        let fullName = [ownerSecondName, ownerFirstName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return ownerUserLogin ?? "Пользователь"
    }

    var parsedCreatedAt: Date? {
        HomeMessageDateParser.parse(createdAt)
    }

    /// Reply в чате заказа — как в основном чате — кодируется префиксом в тексте:
    /// «| Автор\n> цитата\nтело». Бэкенд про reply не знает, это чисто клиентская
    /// конвенция (см. HomeMessage.replyFragment).
    var replyFragment: HomeReplyFragment? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let parts = text.components(separatedBy: "\n")
        guard let firstLine = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), firstLine.hasPrefix("| ") else {
            return nil
        }

        let author = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count > 1 else {
            return HomeReplyFragment(author: author, message: "", body: nil)
        }

        let secondLine = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let replyMessage: String
        if secondLine.hasPrefix("> ") {
            replyMessage = String(secondLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if secondLine.hasPrefix("| ") {
            replyMessage = String(secondLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }

        let bodyLines = Array(parts.dropFirst(2))
        let bodyText = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return HomeReplyFragment(author: author, message: replyMessage, body: bodyText.isEmpty ? nil : bodyText)
    }

    /// Видимый текст сообщения без reply-префикса (тело). Для обычных сообщений — весь текст.
    var visibleText: String {
        if let replyFragment {
            return replyFragment.body ?? ""
        }
        return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Короткая цитата для reply-превью / нового ответа на этот комментарий.
    var replyReferenceText: String {
        let sourceText: String
        if let replyFragment {
            sourceText = replyFragment.body ?? replyFragment.message
        } else if let attachment = attachments.first {
            if attachment.isPhoto {
                sourceText = attachments.count > 1 ? "Фото (\(attachments.count))" : "Фото"
            } else {
                sourceText = attachment.attachmentOriginalFilename
            }
        } else {
            sourceText = text ?? ""
        }

        let collapsedText = sourceText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsedText.isEmpty ? "Сообщение" : collapsedText
    }

    /// Есть ли что копировать (текст, без учёта reply-префикса).
    var hasCopyableText: Bool {
        !visibleText.isEmpty
    }

    var isLocalOnly: Bool {
        id < 0
    }

    var canRetryDelivery: Bool {
        deliveryState == .failed
    }
}

struct HomeOrderCommentCreateRequest: Encodable {
    let orderCommentText: String?
    let attachments: [HomeMessageAttachmentCreateRequest]
    var mentionedUserIDs: [Int] = []

    enum CodingKeys: String, CodingKey {
        case orderCommentText = "order_comment_text"
        case attachments
        case mentionedUserIDs = "mentioned_user_ids"
    }
}

struct HomeOrderCommentUpdateRequest: Encodable {
    let orderCommentText: String
    var mentionedUserIDs: [Int] = []

    enum CodingKeys: String, CodingKey {
        case orderCommentText = "order_comment_text"
        case mentionedUserIDs = "mentioned_user_ids"
    }
}

struct HomeOrderCommentPinRequest: Encodable {
    let orderCommentIsPinned: Bool

    enum CodingKeys: String, CodingKey {
        case orderCommentIsPinned = "order_comment_is_pinned"
    }
}

extension HomeOrderComment {
    static func makeLocalTextComment(id: Int, orderID: Int, text: String, user: AuthUser, deliveryState: HomeMessageDeliveryState) -> HomeOrderComment {
        HomeOrderComment(
            id: id,
            orderID: orderID,
            text: text,
            ownerUserID: user.userID,
            ownerUserLogin: user.userLogin,
            ownerFirstName: user.userFirstName,
            ownerSecondName: user.userSecondName,
            ownerProfilePhoto: user.userProfilePhoto,
            createdAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachments: [],
            deliveryState: deliveryState
        )
    }

    static func makeLocalAttachmentComment(id: Int, orderID: Int, attachment: HomeOrderCommentAttachment, user: AuthUser, deliveryState: HomeMessageDeliveryState) -> HomeOrderComment {
        HomeOrderComment(
            id: id,
            orderID: orderID,
            text: nil,
            ownerUserID: user.userID,
            ownerUserLogin: user.userLogin,
            ownerFirstName: user.userFirstName,
            ownerSecondName: user.userSecondName,
            ownerProfilePhoto: user.userProfilePhoto,
            createdAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachments: [attachment],
            deliveryState: deliveryState
        )
    }
}

struct HomeOrderCommentAttachment: Codable, Hashable, Identifiable {
    let attachmentID: Int
    let attachmentKind: String
    let attachmentOriginalFilename: String
    let attachmentMimeType: String
    let attachmentStorageKey: String
    let attachmentSizeBytes: Int?
    let attachmentCreatedAt: String?
    var attachmentLocalFilePath: String? = nil

    enum CodingKeys: String, CodingKey {
        case attachmentID = "attachment_id"
        case attachmentKind = "attachment_kind"
        case attachmentOriginalFilename = "attachment_original_filename"
        case attachmentMimeType = "attachment_mime_type"
        case attachmentStorageKey = "attachment_storage_key"
        case attachmentSizeBytes = "attachment_size_bytes"
        case attachmentCreatedAt = "attachment_created_at"
    }

    var id: Int { attachmentID }

    var isPhoto: Bool {
        attachmentKind == "photo"
    }

    var localFileURL: URL? {
        guard let attachmentLocalFilePath, !attachmentLocalFilePath.isEmpty else { return nil }
        return URL(fileURLWithPath: attachmentLocalFilePath)
    }

    var mediaURL: URL? {
        localFileURL ?? AppConfig.orderCommentAttachmentURL(for: attachmentID)
    }
}

extension HomeOrderCommentAttachment {
    static func makeLocal(id: Int, kind: String, filename: String, mimeType: String, sizeBytes: Int, localFileURL: URL) -> HomeOrderCommentAttachment {
        HomeOrderCommentAttachment(
            attachmentID: id,
            attachmentKind: kind,
            attachmentOriginalFilename: filename,
            attachmentMimeType: mimeType,
            attachmentStorageKey: "local-\(UUID().uuidString)",
            attachmentSizeBytes: sizeBytes,
            attachmentCreatedAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachmentLocalFilePath: localFileURL.path
        )
    }
}

struct HomeOrderItem: Codable, Identifiable, Hashable {
    let id: Int
    let orderItemProductID: Int?
    let orderItemName: String
    let orderItemArticle: String?
    let orderItemQuantity: Int
    let orderItemPrice: String
    let orderItemStatusID: Int?
    let orderItemStatus: String?
    let orderItemStatusColor: String?
    let orderItemSupplier: String?
    let orderItemNote: String?
    let orderItemSourceEstablishmentID: Int?
    let orderItemSourceEstablishmentName: String?
    let orderItemDestinationEstablishmentID: Int?
    let orderItemDestinationEstablishmentName: String?
    let orderItemCurrencyID: Int?
    let orderItemCheckpointStarted: Bool
    let orderItemCheckpointCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id = "order_item_id"
        case orderItemProductID = "order_item_product_id"
        case orderItemName = "order_item_name"
        case orderItemArticle = "order_item_article"
        case orderItemQuantity = "order_item_quantity"
        case orderItemPrice = "order_item_price"
        case orderItemStatusID = "order_item_status_id"
        case orderItemStatus = "order_item_status"
        case orderItemStatusColor = "order_item_status_color"
        case orderItemSupplier = "order_item_supplier"
        case orderItemNote = "order_item_note"
        case orderItemSourceEstablishmentID = "order_item_source_establishment_id"
        case orderItemSourceEstablishmentName = "order_item_source_establishment_name"
        case orderItemDestinationEstablishmentID = "order_item_destination_establishment_id"
        case orderItemDestinationEstablishmentName = "order_item_destination_establishment_name"
        case orderItemCurrencyID = "order_item_currency_id"
        case orderItemCheckpointStarted = "order_item_checkpoint_started"
        case orderItemCheckpointCompleted = "order_item_checkpoint_completed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        orderItemProductID = try container.decodeIfPresent(Int.self, forKey: .orderItemProductID)
        orderItemName = try container.decode(String.self, forKey: .orderItemName)
        orderItemArticle = try container.decodeIfPresent(String.self, forKey: .orderItemArticle)
        orderItemQuantity = try container.decode(Int.self, forKey: .orderItemQuantity)
        orderItemPrice = try container.decode(String.self, forKey: .orderItemPrice)
        orderItemStatusID = try container.decodeIfPresent(Int.self, forKey: .orderItemStatusID)
        orderItemStatus = try container.decodeIfPresent(String.self, forKey: .orderItemStatus)
        orderItemStatusColor = try container.decodeIfPresent(String.self, forKey: .orderItemStatusColor)
        orderItemSupplier = try container.decodeIfPresent(String.self, forKey: .orderItemSupplier)
        orderItemNote = try container.decodeIfPresent(String.self, forKey: .orderItemNote)
        orderItemSourceEstablishmentID = try container.decodeIfPresent(Int.self, forKey: .orderItemSourceEstablishmentID)
        orderItemSourceEstablishmentName = try container.decodeIfPresent(String.self, forKey: .orderItemSourceEstablishmentName)
        orderItemDestinationEstablishmentID = try container.decodeIfPresent(Int.self, forKey: .orderItemDestinationEstablishmentID)
        orderItemDestinationEstablishmentName = try container.decodeIfPresent(String.self, forKey: .orderItemDestinationEstablishmentName)
        orderItemCurrencyID = try container.decodeIfPresent(Int.self, forKey: .orderItemCurrencyID)
        orderItemCheckpointStarted = try container.decodeIfPresent(Bool.self, forKey: .orderItemCheckpointStarted) ?? false
        orderItemCheckpointCompleted = try container.decodeIfPresent(Bool.self, forKey: .orderItemCheckpointCompleted) ?? false
    }
}

struct HomeOrderItemCreateRequest: Encodable {
    let productID: Int?
    let productArticle: String?
    let productName: String?
    let orderItemQuantity: Int
    let orderItemPrice: String
    let orderItemStatusID: Int?
    let orderItemSupplier: String?
    let orderItemNote: String?
    let orderItemSourceEstablishmentID: Int?
    let orderItemDestinationEstablishmentID: Int?
    let orderItemCurrencyID: Int?
    let orderItemCheckpointStarted: Bool
    let orderItemCheckpointCompleted: Bool

    init(
        productID: Int?,
        productArticle: String?,
        productName: String?,
        orderItemQuantity: Int,
        orderItemPrice: String,
        orderItemStatusID: Int?,
        orderItemSupplier: String? = nil,
        orderItemNote: String? = nil,
        orderItemSourceEstablishmentID: Int? = nil,
        orderItemDestinationEstablishmentID: Int? = nil,
        orderItemCurrencyID: Int?,
        orderItemCheckpointStarted: Bool = false,
        orderItemCheckpointCompleted: Bool = false
    ) {
        self.productID = productID
        self.productArticle = productArticle
        self.productName = productName
        self.orderItemQuantity = orderItemQuantity
        self.orderItemPrice = orderItemPrice
        self.orderItemStatusID = orderItemStatusID
        self.orderItemSupplier = orderItemSupplier
        self.orderItemNote = orderItemNote
        self.orderItemSourceEstablishmentID = orderItemSourceEstablishmentID
        self.orderItemDestinationEstablishmentID = orderItemDestinationEstablishmentID
        self.orderItemCurrencyID = orderItemCurrencyID
        self.orderItemCheckpointStarted = orderItemCheckpointStarted
        self.orderItemCheckpointCompleted = orderItemCheckpointCompleted
    }

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productArticle = "product_article"
        case productName = "product_name"
        case orderItemQuantity = "order_item_quantity"
        case orderItemPrice = "order_item_price"
        case orderItemStatusID = "order_item_status_id"
        case orderItemSupplier = "order_item_supplier"
        case orderItemNote = "order_item_note"
        case orderItemSourceEstablishmentID = "order_item_source_establishment_id"
        case orderItemDestinationEstablishmentID = "order_item_destination_establishment_id"
        case orderItemCurrencyID = "order_item_currency_id"
        case orderItemCheckpointStarted = "order_item_checkpoint_started"
        case orderItemCheckpointCompleted = "order_item_checkpoint_completed"
    }
}

struct HomeOrderUpdateRequest: Encodable {
    let orderEstablishmentID: Int
    let orderMethodID: Int?
    let orderSubMethod: String?
    let orderContactMethod: String?
    let orderSalesChannel: String?
    let orderCustomer: String
    let orderInfo: String
    let orderStatusID: Int
    let items: [HomeOrderItemCreateRequest]

    enum CodingKeys: String, CodingKey {
        case orderEstablishmentID = "order_establishment_id"
        case orderMethodID = "order_method_id"
        case orderSubMethod = "order_sub_method"
        case orderContactMethod = "order_contact_method"
        case orderSalesChannel = "order_sales_channel"
        case orderCustomer = "order_customer"
        case orderInfo = "order_info"
        case orderStatusID = "order_status_id"
        case items
    }
}

struct HomeOrderSplitResponse: Decodable {
    let order: HomeOrder
    let newOrder: HomeOrder

    enum CodingKeys: String, CodingKey {
        case order
        case newOrder = "new_order"
    }
}

struct HomeInventoryCreateRequest: Encodable {
    let inventoryEstablishmentID: Int
    let inventorySupplier: String?
    let saveContact: Bool
    let items: [HomeInventoryItemCreateRequest]

    enum CodingKeys: String, CodingKey {
        case inventoryEstablishmentID = "inventory_establishment_id"
        case inventorySupplier = "inventory_supplier"
        case saveContact = "save_contact"
        case items
    }
}

struct HomeInventory: Codable, Identifiable, Hashable {
    let id: Int
    let inventoryEstablishmentID: Int
    let inventoryEstablishmentName: String?
    let inventorySupplier: String?
    let inventoryStatusID: Int
    let inventoryStatus: String?
    let inventoryStatusColor: String?
    let inventoryCreatedAt: String?
    let items: [HomeInventoryItem]

    enum CodingKeys: String, CodingKey {
        case id = "inventory_id"
        case inventoryEstablishmentID = "inventory_establishment_id"
        case inventoryEstablishmentName = "inventory_establishment_name"
        case inventorySupplier = "inventory_supplier"
        case inventoryStatusID = "inventory_status_id"
        case inventoryStatus = "inventory_status"
        case inventoryStatusColor = "inventory_status_color"
        case inventoryCreatedAt = "inventory_created_at"
        case items
    }
}

struct HomeInventoryItem: Codable, Identifiable, Hashable {
    let id: Int
    let inventoryItemProductID: Int?
    let inventoryItemName: String
    let inventoryItemArticle: String?
    let inventoryItemQuantity: Int
    let inventoryItemCost: String
    let inventoryItemCurrencyID: Int?

    enum CodingKeys: String, CodingKey {
        case id = "inventory_item_id"
        case inventoryItemProductID = "inventory_item_product_id"
        case inventoryItemName = "inventory_item_name"
        case inventoryItemArticle = "inventory_item_article"
        case inventoryItemQuantity = "inventory_item_quantity"
        case inventoryItemCost = "inventory_item_cost"
        case inventoryItemCurrencyID = "inventory_item_currency_id"
    }
}

/// Отметка об оплате заказа: true — «Оплачено», false — снять отметку.
struct HomeOrderPaymentUpdateRequest: Encodable {
    let orderPaid: Bool

    enum CodingKeys: String, CodingKey {
        case orderPaid = "order_paid"
    }
}

struct HomeInventoryStatusUpdateRequest: Encodable {
    let inventoryStatusID: Int

    enum CodingKeys: String, CodingKey {
        case inventoryStatusID = "inventory_status_id"
    }
}

struct HomeInventoryItemCreateRequest: Encodable {
    let productID: Int?
    let productArticle: String?
    let productName: String?
    let inventoryItemQuantity: Int
    let inventoryItemCost: String
    let inventoryItemCurrencyID: Int?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productArticle = "product_article"
        case productName = "product_name"
        case inventoryItemQuantity = "inventory_item_quantity"
        case inventoryItemCost = "inventory_item_cost"
        case inventoryItemCurrencyID = "inventory_item_currency_id"
    }
}

struct HomeProductRegistrationCreateRequest: Encodable {
    let productRegistrationEstablishmentID: Int
    let productRegistrationSupplier: String
    let saveContact: Bool
    let items: [HomeProductRegistrationItemCreateRequest]

    enum CodingKeys: String, CodingKey {
        case productRegistrationEstablishmentID = "product_registration_establishment_id"
        case productRegistrationSupplier = "product_registration_supplier"
        case saveContact = "save_contact"
        case items
    }
}

struct HomeProductRegistration: Codable, Identifiable, Hashable {
    let id: Int
    let productRegistrationEstablishmentID: Int
    let productRegistrationEstablishmentName: String?
    let productRegistrationSupplier: String?
    let productRegistrationStatusID: Int
    let productRegistrationStatus: String?
    let productRegistrationStatusColor: String?
    let productRegistrationCreatedAt: String?
    let items: [HomeProductRegistrationItem]

    enum CodingKeys: String, CodingKey {
        case id = "product_registration_id"
        case productRegistrationEstablishmentID = "product_registration_establishment_id"
        case productRegistrationEstablishmentName = "product_registration_establishment_name"
        case productRegistrationSupplier = "product_registration_supplier"
        case productRegistrationStatusID = "product_registration_status_id"
        case productRegistrationStatus = "product_registration_status"
        case productRegistrationStatusColor = "product_registration_status_color"
        case productRegistrationCreatedAt = "product_registration_created_at"
        case items
    }
}

struct HomeProductRegistrationItem: Codable, Identifiable, Hashable {
    let id: Int
    let productRegistrationItemProductID: Int?
    let productRegistrationItemName: String
    let productRegistrationItemArticle: String?
    let productRegistrationItemQuantity: Int
    let productRegistrationItemCost: String
    let productRegistrationItemCurrencyID: Int?

    enum CodingKeys: String, CodingKey {
        case id = "product_registration_item_id"
        case productRegistrationItemProductID = "product_registration_item_product_id"
        case productRegistrationItemName = "product_registration_item_name"
        case productRegistrationItemArticle = "product_registration_item_article"
        case productRegistrationItemQuantity = "product_registration_item_quantity"
        case productRegistrationItemCost = "product_registration_item_cost"
        case productRegistrationItemCurrencyID = "product_registration_item_currency_id"
    }
}

struct HomeProductRegistrationStatusUpdateRequest: Encodable {
    let productRegistrationStatusID: Int

    enum CodingKeys: String, CodingKey {
        case productRegistrationStatusID = "product_registration_status_id"
    }
}

struct HomeProductRegistrationItemCreateRequest: Encodable {
    let productID: Int?
    let productArticle: String?
    let productName: String?
    let productRegistrationItemQuantity: Int
    let productRegistrationItemCost: String
    let productRegistrationItemCurrencyID: Int?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productArticle = "product_article"
        case productName = "product_name"
        case productRegistrationItemQuantity = "product_registration_item_quantity"
        case productRegistrationItemCost = "product_registration_item_cost"
        case productRegistrationItemCurrencyID = "product_registration_item_currency_id"
    }
}

extension HomeMessage {
    var filterKind: HomeChatFilterKind {
        switch documentKind {
        case "order":
            return .order
        case "inventory":
            return .inventory
        case "product_registration":
            return .productRegistration
        default:
            return .message
        }
    }

    var filterEstablishmentID: Int? {
        if let order {
            return order.orderEstablishmentID
        }
        if let inventory {
            return inventory.inventoryEstablishmentID
        }
        if let productRegistration {
            return productRegistration.productRegistrationEstablishmentID
        }
        return nil
    }

    var filterOrderMethodID: Int? {
        order?.orderMethodID
    }

    var filterStatusID: Int? {
        if let order {
            return order.orderStatusID
        }
        if let inventory {
            return inventory.inventoryStatusID
        }
        if let productRegistration {
            return productRegistration.productRegistrationStatusID
        }
        return nil
    }

    var filterStatusText: String? {
        if let order {
            return order.orderStatus
        }
        if let inventory {
            return inventory.inventoryStatus
        }
        if let productRegistration {
            return productRegistration.productRegistrationStatus
        }
        return messageStatus
    }

    var replyFragment: HomeReplyFragment? {
        guard let text = messageText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let parts = text.components(separatedBy: "\n")
        guard let firstLine = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), firstLine.hasPrefix("| ") else {
            return nil
        }

        let author = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count > 1 else {
            return HomeReplyFragment(author: author, message: "", body: nil)
        }

        let secondLine = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let replyMessage: String
        if secondLine.hasPrefix("> ") {
            replyMessage = String(secondLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if secondLine.hasPrefix("| ") {
            replyMessage = String(secondLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }

        let bodyLines = Array(parts.dropFirst(2))
        let bodyText = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return HomeReplyFragment(author: author, message: replyMessage, body: bodyText.isEmpty ? nil : bodyText)
    }

    var visibleMessageText: String {
        if let replyFragment {
            return replyFragment.body ?? ""
        }
        return messageText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var replyReferenceText: String {
        let sourceText: String
        if let replyFragment {
            sourceText = replyFragment.body ?? replyFragment.message
        } else if let documentReferenceTitle {
            sourceText = documentReferenceTitle
        } else if let attachment = attachments.first {
            if attachment.isPhoto {
                sourceText = attachments.count > 1 ? "Фото (\(attachments.count))" : "Фото"
            } else {
                sourceText = attachment.attachmentOriginalFilename
            }
        } else {
            sourceText = messageText ?? ""
        }

        let collapsedText = sourceText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsedText.isEmpty ? "Сообщение" : collapsedText
    }
}

enum HomeMessageDateParser {
    // Parsing a timestamp tries up to four formatters and is expensive; the same strings are
    // parsed thousands of times per body pass (filtering, sorting, row rendering) over the full
    // cached history. Memoize: each unique timestamp is parsed once, then served O(1). The lock
    // also serializes the non-thread-safe formatters. Timestamps are immutable, so never stale.
    private static let cacheLock = NSLock()
    private static var cache: [String: Date] = [:]

    static func parse(_ timestamp: String?) -> Date? {
        guard let timestamp, !timestamp.isEmpty else { return nil }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[timestamp] { return cached }

        let parsed = timestampFormatterWithFractionalZone.date(from: timestamp)
            ?? timestampFormatterZone.date(from: timestamp)
            ?? timestampFormatterWithMicroseconds.date(from: timestamp)
            ?? timestampFormatterWithoutMicroseconds.date(from: timestamp)

        if let parsed {
            if cache.count > 20_000 { cache.removeAll(keepingCapacity: true) }
            cache[timestamp] = parsed
        }
        return parsed
    }

    private static let timestampFormatterWithFractionalZone: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timestampFormatterZone: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let timestampFormatterWithMicroseconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let timestampFormatterWithoutMicroseconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
