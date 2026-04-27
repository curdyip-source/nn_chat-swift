import Foundation
import LocalAuthentication
import Security

enum AppBiometryType: Equatable {
    case none
    case faceID
    case touchID

    var buttonTitle: String {
        switch self {
        case .faceID:
            return "Войти через Face ID"
        case .touchID:
            return "Войти через Touch ID"
        case .none:
            return "Войти по биометрии"
        }
    }

    var iconName: String {
        switch self {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "person.crop.circle.badge.checkmark"
        }
    }
}

enum BiometricAuthError: LocalizedError {
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Биометрический вход недоступен на этом устройстве"
        case .failed:
            return "Не удалось подтвердить вход по биометрии"
        }
    }
}

struct StoredAuthCredentials: Codable {
    let userLogin: String
    let password: String
}

enum BiometricAuthService {
    static func availableBiometryType() -> AppBiometryType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.unavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evaluateError in
                if success {
                    continuation.resume()
                    return
                }

                if let evaluateError {
                    continuation.resume(throwing: evaluateError)
                } else {
                    continuation.resume(throwing: BiometricAuthError.failed)
                }
            }
        }
    }
}

final class AuthCredentialStore {
    private let service = "com.NufNaf.Vorobev.auth.credentials"
    private let account = "primary"

    var hasStoredCredentials: Bool {
        (try? load()) != nil
    }

    func save(_ credentials: StoredAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        clear()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func load() throws -> StoredAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return try JSONDecoder().decode(StoredAuthCredentials.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}