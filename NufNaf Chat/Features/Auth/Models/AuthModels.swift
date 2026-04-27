//
//  AuthModels.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Foundation

struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

struct APIErrorPayload: Decodable {
    let code: String
    let message: String
}

struct AuthUser: Codable, Equatable {
    let userID: Int
    let userLogin: String
    let userAdmin: Bool
    let userActive: Bool
    let userFirstName: String
    let userSecondName: String
    let userProfilePhoto: String?
    let userAge: Int
    let userAddress: String
    let userVerifiedUserID: Int?
    let userCreatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userLogin = "user_login"
        case userAdmin = "user_admin"
        case userActive = "user_active"
        case userFirstName = "user_first_name"
        case userSecondName = "user_second_name"
        case userProfilePhoto = "user_profile_photo"
        case userAge = "user_age"
        case userAddress = "user_address"
        case userVerifiedUserID = "user_verified_user_id"
        case userCreatedAt = "user_created_at"
    }
}

struct LoginRequest: Encodable {
    let userLogin: String
    let userPassword: String

    enum CodingKeys: String, CodingKey {
        case userLogin = "user_login"
        case userPassword = "user_password"
    }
}

struct RegisterRequest: Encodable {
    let userLogin: String
    let userPassword: String
    let userFirstName: String
    let userSecondName: String

    enum CodingKeys: String, CodingKey {
        case userLogin = "user_login"
        case userPassword = "user_password"
        case userFirstName = "user_first_name"
        case userSecondName = "user_second_name"
    }
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthResponse: Decodable {
    let token: String
    let accessToken: String
    let accessExpiresAt: String?
    let refreshToken: String
    let refreshExpiresAt: String?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case token
        case accessToken = "access_token"
        case accessExpiresAt = "access_expires_at"
        case refreshToken = "refresh_token"
        case refreshExpiresAt = "refresh_expires_at"
        case user
    }
}

struct RegisterResponse: Decodable {
    let message: String
    let user: AuthUser
}

struct AuthMeResponse: Decodable {
    let user: AuthUser
}

struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
}

enum SessionScreenState: Equatable {
    case loading
    case login
    case authenticated(AuthUser)
    case awaitingApproval(AuthUser)
}

enum AuthServiceError: LocalizedError {
    case invalidResponse
    case backend(statusCode: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case let .backend(_, message):
            return message
        case let .transport(message):
            return message
        }
    }
}
