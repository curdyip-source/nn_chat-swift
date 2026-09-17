//
//  HomeAPIClient.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Foundation

struct HomeAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let authClient: AuthAPIClient
    private let storageKey = "auth.session"

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared, defaults: UserDefaults = .standard, authClient: AuthAPIClient? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
        self.authClient = authClient ?? AuthAPIClient(baseURL: baseURL, session: session)
    }

    /// One page of incremental changes since `cursor` (nil/empty = initial full sync).
    func syncMessages(accessToken: String, cursor: String?, limit: Int = 200) async throws -> HomeMessageSyncResponse {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await send(
            path: "messages/sync",
            queryItems: queryItems,
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
    }

    func getMessages(accessToken: String) async throws -> [HomeMessage] {
        // The backend caps `page_size` at 100, so a single request only returns the
        // latest ~100 records. The home feed must show the whole current year, so we
        // page backwards with the `before_message_id` cursor until we've covered it.
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let pageSize = 100
        let safetyPageLimit = 100 // hard stop at 10k messages to avoid runaway loops

        var allItems: [HomeMessage] = []
        var beforeMessageID: Int?

        for _ in 0..<safetyPageLimit {
            var queryItems = [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
            if let beforeMessageID {
                queryItems.append(URLQueryItem(name: "before_message_id", value: String(beforeMessageID)))
            }

            let response: HomeMessageResponse = try await send(
                path: "messages",
                queryItems: queryItems,
                method: "GET",
                body: Optional<String>.none,
                accessToken: accessToken
            )
            let items = response.items
            allItems.append(contentsOf: items)

            // Reached the end of the feed.
            if items.count < pageSize { break }

            // We've paged back past the current year — everything we need is loaded.
            if let oldest = items.last,
               let date = oldest.parsedCreatedAt,
               calendar.component(.year, from: date) < currentYear {
                break
            }

            guard let minID = items.map({ $0.id }).min() else { break }
            beforeMessageID = minID
        }

        return allItems
    }

    func fetchParticipants(accessToken: String) async throws -> [ChatParticipant] {
        let response: ChatParticipantsResponse = try await send(
            path: "users/participants",
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.items
    }

    func sendMessage(accessToken: String, text: String, mentionedUserIDs: [Int] = [], idempotencyKey: String? = nil) async throws -> HomeMessage {
        let response: HomeItemEnvelope<HomeMessage> = try await send(
            path: "messages",
            method: "POST",
            body: HomeMessageCreateRequest(messageType: "message", messageText: text, attachments: [], mentionedUserIDs: mentionedUserIDs),
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
        return response.item
    }

    func sendAttachmentMessage(accessToken: String, attachments: [HomeMessageAttachmentCreateRequest], idempotencyKey: String? = nil) async throws -> HomeMessage {
        let response: HomeItemEnvelope<HomeMessage> = try await send(
            path: "messages",
            method: "POST",
            body: HomeMessageCreateRequest(messageType: "file", messageText: nil, attachments: attachments),
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
        return response.item
    }

    func updateMessage(accessToken: String, messageID: Int, text: String) async throws -> HomeMessage {
        let response: HomeItemEnvelope<HomeMessage> = try await send(
            path: "messages/\(messageID)",
            method: "PUT",
            body: HomeMessageUpdateRequest(messageText: text),
            accessToken: accessToken
        )
        return response.item
    }

    func deleteMessage(accessToken: String, messageID: Int) async throws {
        let _: EmptyAPIResponse = try await send(
            path: "messages/\(messageID)",
            method: "DELETE",
            body: Optional<String>.none,
            accessToken: accessToken
        )
    }

    func getReferenceData(accessToken: String) async throws -> HomeReferenceDataResponse {
        try await send(path: "reference-data", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    // MARK: - Прайс (прокси к nn_vla)

    func priceSuppliers(accessToken: String) async throws -> [PriceSupplier] {
        let response: PriceSuppliersResponse = try await send(
            path: "price/suppliers", method: "GET", body: Optional<String>.none, accessToken: accessToken
        )
        return response.items
    }

    /// Живой поиск по прайс-листам. `emails` — фильтр источников («CL»/email-ы);
    /// пусто = искать по всем.
    func priceSearch(accessToken: String, query: String, emails: [String], strict: Bool = false) async throws -> [PriceSearchResult] {
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "50"),
        ]
        if strict {
            queryItems.append(URLQueryItem(name: "strict", value: "true"))
        }
        for email in emails {
            queryItems.append(URLQueryItem(name: "emails", value: email))
        }
        let response: PriceSearchResponse = try await send(
            path: "price/search",
            queryItems: queryItems,
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.results
    }

    func searchProducts(accessToken: String, query: String) async throws -> [HomeProduct] {
        let response: HomeProductResponse = try await send(
            path: "products",
            queryItems: [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: "20"),
            ],
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.items
    }

    func searchContacts(accessToken: String, contactType: String, query: String) async throws -> [HomeContact] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var queryItems = [
            URLQueryItem(name: "contact_type", value: contactType),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
        ]
        if !normalizedQuery.isEmpty {
            queryItems.insert(URLQueryItem(name: "search", value: query), at: 1)
        }
        let response: HomeContactResponse = try await send(
            path: "contacts",
            queryItems: queryItems,
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.items
    }

    /// Сопоставление списка наименований с номенклатурой (точное совпадение по имени).
    /// История заказа: события аудита заказа и накладных СДЭК, новые сверху.
    func fetchOrderHistory(accessToken: String, orderID: Int) async throws -> [HomeOrderHistoryEntry] {
        let response: HomeOrderHistoryResponse = try await send(
            path: "orders/\(orderID)/history",
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.items
    }

    func matchProductsByName(accessToken: String, names: [String]) async throws -> [HomeProductMatch] {
        let response: HomeProductMatchResponse = try await send(
            path: "products/match",
            method: "POST",
            body: HomeProductMatchRequest(names: names),
            accessToken: accessToken
        )
        return response.results
    }

    func createProduct(accessToken: String, request: HomeProductCreateRequest) async throws -> HomeProduct {
        let response: HomeItemEnvelope<HomeProduct> = try await send(path: "products", method: "POST", body: request, accessToken: accessToken)
        return response.item
    }

    func updateProfile(accessToken: String, request: HomeProfileUpdateRequest) async throws -> AuthUser {
        let response: HomeItemEnvelope<AuthUser> = try await send(path: "users/me/profile", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    func uploadProfilePhoto(accessToken: String, jpegData: Data, filename: String = "profile.jpg") async throws -> AuthUser {
        guard let endpoint = buildURL(path: "users/me/profile-photo", queryItems: []) else {
            throw AuthServiceError.invalidResponse
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let (data, httpResponse) = try await performAuthorizedRequest(accessToken: accessToken) { token in
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = buildMultipartBody(boundary: boundary, filename: filename, fileData: jpegData)
            return request
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AuthServiceError.backend(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(HomeItemEnvelope<AuthUser>.self, from: data).item
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    func uploadMessageAttachment(accessToken: String, data: Data, filename: String, mimeType: String, attachmentKind: String) async throws -> HomeUploadedMessageAttachment {
        guard let endpoint = buildURL(path: "message-attachments", queryItems: []) else {
            throw AuthServiceError.invalidResponse
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let response: HomeItemEnvelope<HomeUploadedMessageAttachment> = try await performAuthorized(accessToken: accessToken) { token in
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = buildMessageAttachmentMultipartBody(
                boundary: boundary,
                attachmentKind: attachmentKind,
                filename: filename,
                mimeType: mimeType,
                fileData: data
            )
            return request
        }
        return response.item
    }

    func downloadAttachment(from url: URL) async throws -> (data: Data, response: HTTPURLResponse) {
        let request = URLRequest(url: url)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthServiceError.transport("Не удалось загрузить вложение")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AuthServiceError.backend(statusCode: httpResponse.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        return (data, httpResponse)
    }

    func registerUserDevice(accessToken: String, token: String, environment: String) async throws {
        let _: HomeItemEnvelope<UserDeviceRegistrationStub> = try await send(
            path: "user-devices",
            method: "POST",
            body: UserDeviceRegisterRequest(userDeviceToken: token, userDevicePlatform: "ios", userDeviceEnvironment: environment),
            accessToken: accessToken
        )
    }

    func createOrder(accessToken: String, request: HomeOrderCreateRequest, idempotencyKey: String? = nil) async throws {
        let _: HomeItemEnvelope<OrderCreateStub> = try await send(path: "orders", method: "POST", body: request, accessToken: accessToken, idempotencyKey: idempotencyKey)
    }

    func getOrder(accessToken: String, orderID: Int) async throws -> HomeOrder {
        let response: HomeItemEnvelope<HomeOrder> = try await send(path: "orders/\(orderID)", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func updateOrder(accessToken: String, orderID: Int, request: HomeOrderUpdateRequest) async throws -> HomeOrder {
        let response: HomeItemEnvelope<HomeOrder> = try await send(path: "orders/\(orderID)", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    func updateOrderPayment(accessToken: String, orderID: Int, paid: Bool) async throws -> HomeOrder {
        let response: HomeItemEnvelope<HomeOrder> = try await send(
            path: "orders/\(orderID)/payment",
            method: "PUT",
            body: HomeOrderPaymentUpdateRequest(orderPaid: paid),
            accessToken: accessToken
        )
        return response.item
    }

    func splitOrder(accessToken: String, orderID: Int) async throws -> HomeOrderSplitResponse {
        return try await send(path: "orders/\(orderID)/split", method: "POST", body: Optional<String>.none, accessToken: accessToken)
    }

    func addOrderComment(accessToken: String, orderID: Int, text: String?, attachments: [HomeMessageAttachmentCreateRequest] = [], mentionedUserIDs: [Int] = [], idempotencyKey: String? = nil) async throws -> HomeOrderComment {
        let response: HomeItemEnvelope<HomeOrderComment> = try await send(
            path: "orders/\(orderID)/comments",
            method: "POST",
            body: HomeOrderCommentCreateRequest(orderCommentText: text, attachments: attachments, mentionedUserIDs: mentionedUserIDs),
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
        return response.item
    }

    func updateOrderComment(accessToken: String, orderID: Int, commentID: Int, text: String, mentionedUserIDs: [Int] = []) async throws -> HomeOrderComment {
        let response: HomeItemEnvelope<HomeOrderComment> = try await send(
            path: "orders/\(orderID)/comments/\(commentID)",
            method: "PUT",
            body: HomeOrderCommentUpdateRequest(orderCommentText: text, mentionedUserIDs: mentionedUserIDs),
            accessToken: accessToken
        )
        return response.item
    }

    func setOrderCommentPinned(accessToken: String, orderID: Int, commentID: Int, pinned: Bool) async throws -> HomeOrderComment {
        let response: HomeItemEnvelope<HomeOrderComment> = try await send(
            path: "orders/\(orderID)/comments/\(commentID)/pin",
            method: "PUT",
            body: HomeOrderCommentPinRequest(orderCommentIsPinned: pinned),
            accessToken: accessToken
        )
        return response.item
    }

    func deleteOrderComment(accessToken: String, orderID: Int, commentID: Int) async throws {
        let _: EmptyAPIResponse = try await send(
            path: "orders/\(orderID)/comments/\(commentID)",
            method: "DELETE",
            body: Optional<String>.none,
            accessToken: accessToken
        )
    }

    // MARK: - Тудулист

    func getTodoBoard(accessToken: String) async throws -> TodoBoardResponse {
        try await send(path: "todos", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func createTodo(accessToken: String, request: TodoCreateRequest) async throws -> TodoItem {
        let response: HomeItemEnvelope<TodoItem> = try await send(path: "todos", method: "POST", body: request, accessToken: accessToken)
        return response.item
    }

    func createTodo(accessToken: String, title: String, listID: Int?, orderID: Int? = nil) async throws -> TodoItem {
        try await createTodo(accessToken: accessToken, request: TodoCreateRequest(title: title, listID: listID, orderID: orderID))
    }

    func updateTodo(accessToken: String, todoID: Int, request: TodoUpdateRequest) async throws -> TodoItem {
        let response: HomeItemEnvelope<TodoItem> = try await send(path: "todos/\(todoID)", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    func setTodoCompleted(accessToken: String, todoID: Int, completed: Bool) async throws -> TodoItem {
        let response: HomeItemEnvelope<TodoItem> = try await send(
            path: "todos/\(todoID)",
            method: "PUT",
            body: TodoCompletionRequest(completed: completed),
            accessToken: accessToken
        )
        return response.item
    }

    func setTodoArchived(accessToken: String, todoID: Int, archived: Bool) async throws -> TodoItem {
        let response: HomeItemEnvelope<TodoItem> = try await send(
            path: "todos/\(todoID)",
            method: "PUT",
            body: TodoArchiveRequest(archived: archived),
            accessToken: accessToken
        )
        return response.item
    }

    func deleteTodo(accessToken: String, todoID: Int) async throws {
        let _: EmptyAPIResponse = try await send(path: "todos/\(todoID)", method: "DELETE", body: Optional<String>.none, accessToken: accessToken)
    }

    func reorderTodos(accessToken: String, order: [Int]) async throws -> TodoBoardResponse {
        let items = order.enumerated().map { TodoReorderRequest.Item(id: $0.element, position: $0.offset) }
        return try await send(path: "todos/reorder", method: "PUT", body: TodoReorderRequest(items: items), accessToken: accessToken)
    }

    func createTodoList(accessToken: String, name: String) async throws -> TodoListItem {
        let response: HomeItemEnvelope<TodoListItem> = try await send(
            path: "todo-lists",
            method: "POST",
            body: TodoListNameRequest(name: name),
            accessToken: accessToken
        )
        return response.item
    }

    func renameTodoList(accessToken: String, listID: Int, name: String) async throws -> TodoListItem {
        let response: HomeItemEnvelope<TodoListItem> = try await send(
            path: "todo-lists/\(listID)",
            method: "PUT",
            body: TodoListNameRequest(name: name),
            accessToken: accessToken
        )
        return response.item
    }

    func deleteTodoList(accessToken: String, listID: Int) async throws {
        let _: EmptyAPIResponse = try await send(path: "todo-lists/\(listID)", method: "DELETE", body: Optional<String>.none, accessToken: accessToken)
    }

    func createInventory(accessToken: String, request: HomeInventoryCreateRequest, idempotencyKey: String? = nil) async throws {
        let _: HomeItemEnvelope<InventoryCreateStub> = try await send(path: "inventories", method: "POST", body: request, accessToken: accessToken, idempotencyKey: idempotencyKey)
    }

    func getInventory(accessToken: String, inventoryID: Int) async throws -> HomeInventory {
        let response: HomeItemEnvelope<HomeInventory> = try await send(path: "inventories/\(inventoryID)", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func updateInventoryStatus(accessToken: String, inventoryID: Int, request: HomeInventoryStatusUpdateRequest) async throws -> HomeInventory {
        let response: HomeItemEnvelope<HomeInventory> = try await send(path: "inventories/\(inventoryID)/status", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    func createProductRegistration(accessToken: String, request: HomeProductRegistrationCreateRequest, idempotencyKey: String? = nil) async throws {
        let _: HomeItemEnvelope<ProductRegistrationCreateStub> = try await send(path: "product-registrations", method: "POST", body: request, accessToken: accessToken, idempotencyKey: idempotencyKey)
    }

    func getProductRegistration(accessToken: String, productRegistrationID: Int) async throws -> HomeProductRegistration {
        let response: HomeItemEnvelope<HomeProductRegistration> = try await send(path: "product-registrations/\(productRegistrationID)", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func updateProductRegistrationStatus(accessToken: String, productRegistrationID: Int, request: HomeProductRegistrationStatusUpdateRequest) async throws -> HomeProductRegistration {
        let response: HomeItemEnvelope<HomeProductRegistration> = try await send(path: "product-registrations/\(productRegistrationID)/status", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    // MARK: - СДЭК

    func suggestCdekCities(accessToken: String, query: String) async throws -> [CdekCity] {
        let response: CdekCitiesResponse = try await send(
            path: "cdek/cities/suggest",
            queryItems: [URLQueryItem(name: "name", value: query)],
            method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.items
    }

    func fetchCdekDeliveryPoints(accessToken: String, cityCode: Int, query: String?) async throws -> [CdekPvz] {
        var items = [URLQueryItem(name: "city_code", value: String(cityCode))]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        let response: CdekPvzResponse = try await send(
            path: "cdek/delivery-points", queryItems: items,
            method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.items
    }

    func fetchCdekTariffs(accessToken: String, toCode: Int, weight: Int, fromCode: Int? = nil) async throws -> [CdekTariff] {
        var query = [URLQueryItem(name: "to_code", value: String(toCode)), URLQueryItem(name: "weight", value: String(weight))]
        if let fromCode { query.append(URLQueryItem(name: "from_code", value: String(fromCode))) }
        let response: CdekTariffsResponse = try await send(
            path: "cdek/tariffs",
            queryItems: query,
            method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.items
    }

    func createCdekWaybill(accessToken: String, orderID: Int, request: CdekWaybillCreateRequest) async throws -> HomeOrderCdek {
        let response: HomeItemEnvelope<HomeOrderCdek> = try await send(
            path: "cdek/orders/\(orderID)/waybill", method: "POST", body: request,
            accessToken: accessToken, idempotencyKey: UUID().uuidString)
        return response.item
    }

    func cdekWaybillStatus(accessToken: String, orderID: Int) async throws -> HomeOrderCdek {
        let response: HomeItemEnvelope<HomeOrderCdek> = try await send(
            path: "cdek/orders/\(orderID)/status", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func deleteCdekWaybill(accessToken: String, orderID: Int) async throws -> HomeOrderCdek {
        let response: HomeItemEnvelope<HomeOrderCdek> = try await send(
            path: "cdek/orders/\(orderID)/waybill", method: "DELETE", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func cdekDefaults(accessToken: String) async throws -> CdekOriginDefault {
        let response: HomeItemEnvelope<CdekOriginDefault> = try await send(
            path: "cdek/defaults", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func cdekPrefill(accessToken: String, customer: String) async throws -> CdekPrefill {
        let response: HomeItemEnvelope<CdekPrefill> = try await send(
            path: "cdek/prefill",
            queryItems: [URLQueryItem(name: "customer", value: customer)],
            method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: RequestBody?,
        accessToken: String,
        idempotencyKey: String? = nil
    ) async throws -> ResponseBody {
        guard let endpoint = buildURL(path: path, queryItems: queryItems) else {
            throw AuthServiceError.invalidResponse
        }
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        let (data, httpResponse) = try await performAuthorizedRequest(accessToken: accessToken) { token in
            var request = URLRequest(url: endpoint)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // A stable per-create key lets the server discard a duplicate POST whose first response
            // was lost (network/VPN drop) and that the client re-sent — see execute()/isSafeToRetry.
            if let idempotencyKey {
                request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            }
            request.httpBody = encodedBody
            return request
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AuthServiceError.backend(statusCode: httpResponse.statusCode, message: message)
        }

        if data.isEmpty, ResponseBody.self == EmptyAPIResponse.self {
            return EmptyAPIResponse() as! ResponseBody
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private func performAuthorized<ResponseBody: Decodable>(
        accessToken: String,
        requestBuilder: @escaping (String) throws -> URLRequest
    ) async throws -> ResponseBody {
        let (data, httpResponse) = try await performAuthorizedRequest(accessToken: accessToken, requestBuilder: requestBuilder)

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AuthServiceError.backend(statusCode: httpResponse.statusCode, message: message)
        }

        if data.isEmpty, ResponseBody.self == EmptyAPIResponse.self {
            return EmptyAPIResponse() as! ResponseBody
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private func performAuthorizedRequest(
        accessToken: String,
        requestBuilder: @escaping (String) throws -> URLRequest
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let initialRequest = try requestBuilder(accessToken)
        let initialResult = try await execute(request: initialRequest)

        guard initialResult.response.statusCode == 401,
              let refreshedAccessToken = try await refreshAccessTokenIfNeeded(expiredAccessToken: accessToken) else {
            return initialResult
        }

        let retriedRequest = try requestBuilder(refreshedAccessToken)
        return try await execute(request: retriedRequest)
    }

    private func execute(request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // A stale keep-alive socket (device slept, network switched) makes the FIRST request
            // fail with a transient transport error even though the server is reachable. Retry
            // once — a fresh connection almost always succeeds — before surfacing the error.
            //
            // IMPORTANT: only retry requests that are safe to re-send. A transient error does NOT
            // mean the request never reached the server: a POST whose body was processed server-side
            // but whose response was lost would be re-sent and silently DUPLICATE the write
            // (duplicate orders / chat messages / attachments). Idempotent methods (GET/HEAD/PUT/
            // DELETE) are always safe; non-idempotent POSTs are safe ONLY when they carry an
            // Idempotency-Key the server uses to discard the duplicate. Everything else surfaces as
            // .failed and is retried explicitly by the user.
            if Self.isRetriableTransportError(error), Self.isSafeToRetry(request) {
                do {
                    (data, response) = try await session.data(for: request)
                } catch {
                    throw AuthServiceError.transport("Не удалось связаться с сервером")
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AuthServiceError.invalidResponse
                }
                return (data, httpResponse)
            }
            throw AuthServiceError.transport("Не удалось связаться с сервером")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        return (data, httpResponse)
    }

    /// Whether a request can be safely re-sent after a transient transport failure. Idempotent
    /// methods (GET/HEAD/PUT/DELETE) always qualify. A non-idempotent POST qualifies only when it
    /// carries an Idempotency-Key — the server then discards the duplicate instead of creating a
    /// second entity if the first request had already succeeded with a lost response.
    private static func isSafeToRetry(_ request: URLRequest) -> Bool {
        switch (request.httpMethod ?? "GET").uppercased() {
        case "GET", "HEAD", "PUT", "DELETE", "OPTIONS":
            return true
        default:
            return request.value(forHTTPHeaderField: "Idempotency-Key") != nil
        }
    }

    /// Transport failures that typically clear on an immediate retry (dropped pooled connection,
    /// transient timeout) rather than a real outage like being offline.
    private static func isRetriableTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func refreshAccessTokenIfNeeded(expiredAccessToken: String) async throws -> String? {
        guard var storedSession = loadStoredSession(), storedSession.accessToken == expiredAccessToken else {
            return nil
        }

        let response = try await authClient.refresh(refreshToken: storedSession.refreshToken)
        storedSession = StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            user: response.user
        )
        saveStoredSession(storedSession)
        return storedSession.accessToken
    }

    private func loadStoredSession() -> StoredSession? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private func saveStoredSession(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func buildURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        let pathComponents = path.split(separator: "/").map(String.init)
        let endpoint = pathComponents.reduce(baseURL) { partialURL, component in
            partialURL.appending(path: component)
        }

        guard !queryItems.isEmpty else {
            return endpoint
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = queryItems
        return components.url
    }

    private func buildMultipartBody(boundary: String, filename: String, fileData: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func buildMessageAttachmentMultipartBody(boundary: String, attachmentKind: String, filename: String, mimeType: String, fileData: Data) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"attachment_kind\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(attachmentKind)\r\n".data(using: .utf8)!)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

private struct OrderCreateStub: Decodable {}
private struct InventoryCreateStub: Decodable {}
private struct ProductRegistrationCreateStub: Decodable {}
private struct UserDeviceRegistrationStub: Decodable {}
private struct EmptyAPIResponse: Decodable {}

private struct UserDeviceRegisterRequest: Encodable {
    let userDeviceToken: String
    let userDevicePlatform: String
    let userDeviceEnvironment: String

    enum CodingKeys: String, CodingKey {
        case userDeviceToken = "user_device_token"
        case userDevicePlatform = "user_device_platform"
        case userDeviceEnvironment = "user_device_environment"
    }
}
