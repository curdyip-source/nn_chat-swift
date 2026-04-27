//
//  AuthAPIClient.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Foundation

struct AuthAPIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func login(userLogin: String, password: String) async throws -> AuthResponse {
        try await send(
            path: "auth/login",
            method: "POST",
            body: LoginRequest(userLogin: userLogin, userPassword: password),
            authorizedWith: nil,
            responseType: AuthResponse.self
        )
    }

    func register(userLogin: String, password: String, firstName: String, secondName: String) async throws -> RegisterResponse {
        try await send(
            path: "auth/register",
            method: "POST",
            body: RegisterRequest(
                userLogin: userLogin,
                userPassword: password,
                userFirstName: firstName,
                userSecondName: secondName
            ),
            authorizedWith: nil,
            responseType: RegisterResponse.self
        )
    }

    func me(accessToken: String) async throws -> AuthMeResponse {
        try await send(
            path: "auth/me",
            method: "GET",
            body: Optional<String>.none,
            authorizedWith: accessToken,
            responseType: AuthMeResponse.self
        )
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await send(
            path: "auth/refresh",
            method: "POST",
            body: RefreshTokenRequest(refreshToken: refreshToken),
            authorizedWith: nil,
            responseType: AuthResponse.self
        )
    }

    func logout(accessToken: String) async {
        _ = try? await send(
            path: "auth/logout",
            method: "POST",
            body: Optional<String>.none,
            authorizedWith: accessToken,
            responseType: EmptyResponse.self
        )
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?,
        authorizedWith token: String?,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let endpoint = baseURL.appending(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

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
            let message = decodeBackendMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AuthServiceError.backend(statusCode: httpResponse.statusCode, message: message)
        }

        if ResponseBody.self == EmptyResponse.self {
            return EmptyResponse() as! ResponseBody
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private func decodeBackendMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message
    }
}

private struct EmptyResponse: Decodable {}
