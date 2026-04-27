//
//  AppSession.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Combine
import Foundation
import LocalAuthentication

struct AppDocumentDestination: Equatable {
    let kind: String
    let id: Int
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var screenState: SessionScreenState = .loading
    @Published private(set) var isBusy = false
    @Published var authErrorMessage: String?
    @Published var isProfileOpen = false
    @Published var isChecklistOpen = false
    @Published var activeDocument: AppDocumentDestination?
    @Published private(set) var chatFilterState = HomeChatFilterState.default()
    @Published var isChatFilterPresented = false

    private let client: AuthAPIClient
    private let defaults: UserDefaults
    private let credentialStore = AuthCredentialStore()
    private let storageKey = "auth.session"

    init(client: AuthAPIClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    convenience init() {
        self.init(client: AuthAPIClient(), defaults: .standard)
    }

    func restoreSession() async {
        guard let storedSession = loadStoredSession() else {
            screenState = .login
            return
        }

        do {
            let meResponse = try await client.me(accessToken: storedSession.accessToken)
            saveStoredSession(StoredSession(
                accessToken: storedSession.accessToken,
                refreshToken: storedSession.refreshToken,
                user: meResponse.user
            ))
            screenState = .authenticated(meResponse.user)
            loadChatFilterState(for: meResponse.user.userID)
        } catch let error as AuthServiceError {
            switch error {
            case let .backend(statusCode, _) where statusCode == 401:
                await refreshSession(using: storedSession.refreshToken, fallbackUser: storedSession.user)
            case let .backend(_, message) where message.localizedCaseInsensitiveContains("деактивирован"):
                clearStoredSession()
                screenState = .awaitingApproval(storedSession.user)
            default:
                clearStoredSession()
                authErrorMessage = error.errorDescription
                screenState = .login
            }
        } catch {
            clearStoredSession()
            authErrorMessage = "Не удалось восстановить сессию"
            screenState = .login
        }
    }

    func login(userLogin: String, password: String) async {
        _ = await performLogin(userLogin: userLogin, password: password)
    }

    func loginWithBiometrics() async {
        authErrorMessage = nil

        do {
            guard biometricLoginType != .none else {
                authErrorMessage = "Биометрический вход недоступен"
                return
            }

            let credentials = try credentialStore.load()
            try await BiometricAuthService.authenticate(reason: "Войти в NufNaf")
            _ = await performLogin(userLogin: credentials.userLogin, password: credentials.password)
        } catch let error as BiometricAuthError {
            authErrorMessage = error.errorDescription
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                break
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                authErrorMessage = "Биометрический вход сейчас недоступен"
            default:
                authErrorMessage = "Не удалось выполнить вход через биометрию"
            }
        } catch {
            authErrorMessage = "Не удалось выполнить вход через биометрию"
        }
    }

    var biometricLoginType: AppBiometryType {
        guard credentialStore.hasStoredCredentials else { return .none }
        return BiometricAuthService.availableBiometryType()
    }

    @discardableResult
    private func performLogin(userLogin: String, password: String) async -> Bool {
        authErrorMessage = nil
        isBusy = true
        isProfileOpen = false
        isChecklistOpen = false
        activeDocument = nil
        defer { isBusy = false }

        do {
            let response = try await client.login(userLogin: userLogin, password: password)
            let storedSession = StoredSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                user: response.user
            )
            saveStoredSession(storedSession)
            try? credentialStore.save(StoredAuthCredentials(userLogin: userLogin, password: password))
            screenState = .authenticated(response.user)
            loadChatFilterState(for: response.user.userID)
            return true
        } catch let error as AuthServiceError {
            handleLoginError(error, attemptedLogin: userLogin)
        } catch {
            authErrorMessage = "Не удалось выполнить вход"
        }

        return false
    }

    func register(userLogin: String, password: String, firstName: String, secondName: String) async {
        authErrorMessage = nil
        isBusy = true
        isProfileOpen = false
        isChecklistOpen = false
        activeDocument = nil
        defer { isBusy = false }

        do {
            let response = try await client.register(
                userLogin: userLogin,
                password: password,
                firstName: firstName,
                secondName: secondName
            )
            clearStoredSession()
            screenState = .awaitingApproval(response.user)
        } catch let error as AuthServiceError {
            authErrorMessage = error.errorDescription
        } catch {
            authErrorMessage = "Не удалось завершить регистрацию"
        }
    }

    func logout() async {
        let accessToken = loadStoredSession()?.accessToken
        clearStoredSession()
        screenState = .login
        authErrorMessage = nil
        isProfileOpen = false
        isChecklistOpen = false
        activeDocument = nil
        isChatFilterPresented = false
        chatFilterState = HomeChatFilterState.default()

        if let accessToken {
            await client.logout(accessToken: accessToken)
        }
    }

    func showLogin() {
        authErrorMessage = nil
        screenState = .login
        isProfileOpen = false
        isChecklistOpen = false
        activeDocument = nil
        isChatFilterPresented = false
        chatFilterState = HomeChatFilterState.default()
    }

    func clearAuthError() {
        authErrorMessage = nil
    }

    var currentAccessToken: String? {
        loadStoredSession()?.accessToken
    }

    var currentUser: AuthUser? {
        switch screenState {
        case let .authenticated(user):
            return user
        case let .awaitingApproval(user):
            return user
        default:
            return nil
        }
    }

    func updateAuthenticatedUser(_ user: AuthUser) {
        guard var storedSession = loadStoredSession() else {
            screenState = .authenticated(user)
            return
        }
        storedSession = StoredSession(
            accessToken: storedSession.accessToken,
            refreshToken: storedSession.refreshToken,
            user: user
        )
        saveStoredSession(storedSession)
        screenState = .authenticated(user)
        loadChatFilterState(for: user.userID)
    }

    func openProfile() {
        guard currentUser != nil else { return }
        activeDocument = nil
        isChatFilterPresented = false
        isChecklistOpen = false
        isProfileOpen = true
    }

    func toggleProfile() {
        guard currentUser != nil else { return }
        if isProfileOpen {
            closeProfile()
        } else {
            openProfile()
        }
    }

    func closeProfile() {
        isProfileOpen = false
    }

    func openChecklist() {
        guard currentUser != nil else { return }
        guard chatFilterState.displayMode == .crm else { return }
        activeDocument = nil
        isChatFilterPresented = false
        isProfileOpen = false
        isChecklistOpen = true
    }

    func toggleChecklist() {
        guard currentUser != nil else { return }
        guard chatFilterState.displayMode == .crm else { return }
        if isChecklistOpen {
            closeChecklist()
        } else {
            openChecklist()
        }
    }

    func closeChecklist() {
        isChecklistOpen = false
    }

    func openDocument(kind: String, id: Int) {
        isProfileOpen = false
        isChecklistOpen = false
        isChatFilterPresented = false
        activeDocument = AppDocumentDestination(kind: kind, id: id)
    }

    func closeDocument() {
        activeDocument = nil
    }

    func toggleChatFilterPanel() {
        guard currentUser != nil else { return }
        activeDocument = nil
        isProfileOpen = false
        isChecklistOpen = false
        isChatFilterPresented.toggle()
    }

    func closeChatFilterPanel() {
        isChatFilterPresented = false
    }

    func updateChatFilterState(_ state: HomeChatFilterState) {
        chatFilterState = state
        saveChatFilterStateIfPossible()
    }

    func resetChatFilterState() {
        updateChatFilterState(.default())
    }

    private func refreshSession(using refreshToken: String, fallbackUser: AuthUser) async {
        do {
            let response = try await client.refresh(refreshToken: refreshToken)
            let storedSession = StoredSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                user: response.user
            )
            saveStoredSession(storedSession)
            screenState = .authenticated(response.user)
        } catch let error as AuthServiceError {
            if case let .backend(_, message) = error,
               message.localizedCaseInsensitiveContains("деактивирован") {
                clearStoredSession()
                screenState = .awaitingApproval(fallbackUser)
                return
            }

            clearStoredSession()
            authErrorMessage = error.errorDescription
            screenState = .login
        } catch {
            clearStoredSession()
            authErrorMessage = "Сессия истекла, войдите снова"
            screenState = .login
        }
    }

    private func handleLoginError(_ error: AuthServiceError, attemptedLogin: String) {
        switch error {
        case let .backend(statusCode, message) where statusCode == 403 && message.localizedCaseInsensitiveContains("деактивирован"):
            clearStoredSession()
            let inactiveUser = AuthUser(
                userID: 0,
                userLogin: attemptedLogin,
                userAdmin: false,
                userActive: false,
                userFirstName: "",
                userSecondName: "",
                userProfilePhoto: nil,
                userAge: 0,
                userAddress: "",
                userVerifiedUserID: nil,
                userCreatedAt: nil
            )
            screenState = .awaitingApproval(inactiveUser)
        default:
            authErrorMessage = error.errorDescription
        }
    }

    private func loadStoredSession() -> StoredSession? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private func saveStoredSession(_ session: StoredSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func chatFilterStorageKey(for userID: Int) -> String {
        "chat.filter-state.\(userID)"
    }

    private func loadChatFilterState(for userID: Int) {
        guard let data = defaults.data(forKey: chatFilterStorageKey(for: userID)),
              let state = try? JSONDecoder().decode(HomeChatFilterState.self, from: data) else {
            chatFilterState = .default()
            return
        }
        chatFilterState = state
    }

    private func saveChatFilterStateIfPossible() {
        guard let userID = currentUser?.userID,
              let data = try? JSONEncoder().encode(chatFilterState) else {
            return
        }
        defaults.set(data, forKey: chatFilterStorageKey(for: userID))
    }

    private func clearStoredSession() {
        defaults.removeObject(forKey: storageKey)
    }
}
