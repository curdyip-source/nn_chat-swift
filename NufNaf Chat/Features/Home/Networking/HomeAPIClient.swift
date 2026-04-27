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

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func getMessages(accessToken: String) async throws -> [HomeMessage] {
        let response: HomeMessageResponse = try await send(
            path: "messages",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: "100"),
            ],
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.items
    }

    func sendMessage(accessToken: String, text: String) async throws -> HomeMessage {
        let response: HomeItemEnvelope<HomeMessage> = try await send(
            path: "messages",
            method: "POST",
            body: HomeMessageCreateRequest(messageType: "message", messageText: text, attachments: []),
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(boundary: boundary, filename: filename, fileData: jpegData)

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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMessageAttachmentMultipartBody(
            boundary: boundary,
            attachmentKind: attachmentKind,
            filename: filename,
            mimeType: mimeType,
            fileData: data
        )

        let response: HomeItemEnvelope<HomeUploadedMessageAttachment> = try await perform(request: request)
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

    func registerUserDevice(accessToken: String, token: String) async throws {
        let _: HomeItemEnvelope<UserDeviceRegistrationStub> = try await send(
            path: "user-devices",
            method: "POST",
            body: UserDeviceRegisterRequest(userDeviceToken: token, userDevicePlatform: "ios"),
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

    func getOrderComments(accessToken: String, orderID: Int) async throws -> [HomeOrderComment] {
        let response: HomeOrderCommentListResponse = try await send(
            path: "orders/\(orderID)/comments",
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
        return response.items
    }

    func addOrderComment(accessToken: String, orderID: Int, text: String?, attachments: [HomeMessageAttachmentCreateRequest] = []) async throws -> HomeOrderComment {
        let response: HomeItemEnvelope<HomeOrderComment> = try await send(
            path: "orders/\(orderID)/comments",
            method: "POST",
            body: HomeOrderCommentCreateRequest(orderCommentText: text, attachments: attachments),
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

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

    private func perform<ResponseBody: Decodable>(request: URLRequest) async throws -> ResponseBody {
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

    enum CodingKeys: String, CodingKey {
        case userDeviceToken = "user_device_token"
        case userDevicePlatform = "user_device_platform"
    }
}
