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

    func sendMessage(accessToken: String, text: String, mentionedUserIDs: [Int] = []) async throws -> HomeMessage {
        let response: HomeItemEnvelope<HomeMessage> = try await send(
            path: "messages",
            method: "POST",
            body: HomeMessageCreateRequest(messageType: "message", messageText: text, attachments: [], mentionedUserIDs: mentionedUserIDs),
            accessToken: accessToken
        )
        return response.item
    }

    func sendAttachmentMessage(accessToken: String, attachments: [HomeMessageAttachmentCreateRequest]) async throws -> HomeMessage {
        let response: HomeItemEnvelope<HomeMessage> = try await send(
            path: "messages",
            method: "POST",
            body: HomeMessageCreateRequest(messageType: "file", messageText: nil, attachments: attachments),
            accessToken: accessToken
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

    func createOrder(accessToken: String, request: HomeOrderCreateRequest) async throws {
        let _: HomeItemEnvelope<OrderCreateStub> = try await send(path: "orders", method: "POST", body: request, accessToken: accessToken)
    }

    func getOrder(accessToken: String, orderID: Int) async throws -> HomeOrder {
        let response: HomeItemEnvelope<HomeOrder> = try await send(path: "orders/\(orderID)", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func updateOrder(accessToken: String, orderID: Int, request: HomeOrderUpdateRequest) async throws -> HomeOrder {
        let response: HomeItemEnvelope<HomeOrder> = try await send(path: "orders/\(orderID)", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    func addOrderComment(accessToken: String, orderID: Int, text: String?, attachments: [HomeMessageAttachmentCreateRequest] = [], mentionedUserIDs: [Int] = []) async throws -> HomeOrderComment {
        let response: HomeItemEnvelope<HomeOrderComment> = try await send(
            path: "orders/\(orderID)/comments",
            method: "POST",
            body: HomeOrderCommentCreateRequest(orderCommentText: text, attachments: attachments, mentionedUserIDs: mentionedUserIDs),
            accessToken: accessToken
        )
        return response.item
    }

    func createInventory(accessToken: String, request: HomeInventoryCreateRequest) async throws {
        let _: HomeItemEnvelope<InventoryCreateStub> = try await send(path: "inventories", method: "POST", body: request, accessToken: accessToken)
    }

    func getInventory(accessToken: String, inventoryID: Int) async throws -> HomeInventory {
        let response: HomeItemEnvelope<HomeInventory> = try await send(path: "inventories/\(inventoryID)", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func updateInventoryStatus(accessToken: String, inventoryID: Int, request: HomeInventoryStatusUpdateRequest) async throws -> HomeInventory {
        let response: HomeItemEnvelope<HomeInventory> = try await send(path: "inventories/\(inventoryID)/status", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    func createProductRegistration(accessToken: String, request: HomeProductRegistrationCreateRequest) async throws {
        let _: HomeItemEnvelope<ProductRegistrationCreateStub> = try await send(path: "product-registrations", method: "POST", body: request, accessToken: accessToken)
    }

    func getProductRegistration(accessToken: String, productRegistrationID: Int) async throws -> HomeProductRegistration {
        let response: HomeItemEnvelope<HomeProductRegistration> = try await send(path: "product-registrations/\(productRegistrationID)", method: "GET", body: Optional<String>.none, accessToken: accessToken)
        return response.item
    }

    func updateProductRegistrationStatus(accessToken: String, productRegistrationID: Int, request: HomeProductRegistrationStatusUpdateRequest) async throws -> HomeProductRegistration {
        let response: HomeItemEnvelope<HomeProductRegistration> = try await send(path: "product-registrations/\(productRegistrationID)/status", method: "PUT", body: request, accessToken: accessToken)
        return response.item
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: RequestBody?,
        accessToken: String
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
            throw AuthServiceError.transport("Не удалось связаться с сервером")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        return (data, httpResponse)
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
