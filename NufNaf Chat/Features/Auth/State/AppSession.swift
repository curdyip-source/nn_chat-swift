//
//  AppSession.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Combine
import Foundation
import SwiftUI
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
    @Published var crmSearchQuery = ""

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
                user: meResponse.user,
                accessExpiresAt: storedSession.accessExpiresAt,
                refreshExpiresAt: storedSession.refreshExpiresAt
            ))
            setAuthenticated(meResponse.user)
        } catch let error as AuthServiceError {
            switch error {
            case let .backend(statusCode, message):
                if statusCode == 401 {
                    // Access-токен протух — обновляем по refresh-токену.
                    switch await refreshTokens() {
                    case let .success(user):
                        setAuthenticated(user)
                    case .invalidSession:
                        handleInvalidSession(message: "Сессия истекла, войдите снова")
                    case .transient:
                        // Сеть/временный сбой — не выкидываем на логин, работаем по
                        // сохранённой сессии; планировщик повторит рефреш.
                        setAuthenticated(storedSession.user)
                    }
                } else if message.localizedCaseInsensitiveContains("деактивирован") {
                    clearStoredSession()
                    screenState = .awaitingApproval(storedSession.user)
                } else if statusCode >= 500 {
                    // Серверный сбой — не разлогиниваем.
                    setAuthenticated(storedSession.user)
                } else {
                    clearStoredSession()
                    authErrorMessage = error.errorDescription
                    screenState = .login
                }
            case .transport, .invalidResponse:
                // Временная (сетевая) ошибка — оставляем пользователя в системе.
                setAuthenticated(storedSession.user)
            }
        } catch {
            // Неизвестная (вероятно сетевая) ошибка — не разлогиниваем.
            setAuthenticated(storedSession.user)
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
            saveStoredSession(storedSession(from: response))
            try? credentialStore.save(StoredAuthCredentials(userLogin: userLogin, password: password))
            setAuthenticated(response.user)
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
        stopTokenRefreshScheduler()
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
        stopTokenRefreshScheduler()
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
            user: user,
            accessExpiresAt: storedSession.accessExpiresAt,
            refreshExpiresAt: storedSession.refreshExpiresAt
        )
        saveStoredSession(storedSession)
        screenState = .authenticated(user)
        loadChatFilterState(for: user.userID)
    }

    /// Реалтайм-обновление прав: перечитываем /me и обновляем пользователя в сессии.
    /// НЕ трогаем chatFilterState (в т.ч. текущий режим) — гейтинг недоступного режима
    /// делает HomeView через onChange(currentUser). Ошибки/сеть — молча игнорируем.
    func refreshCurrentUser() async {
        guard let accessToken = currentAccessToken else { return }
        guard let meResponse = try? await client.me(accessToken: accessToken) else { return }
        if var storedSession = loadStoredSession() {
            storedSession = StoredSession(
                accessToken: storedSession.accessToken,
                refreshToken: storedSession.refreshToken,
                user: meResponse.user,
                accessExpiresAt: storedSession.accessExpiresAt,
                refreshExpiresAt: storedSession.refreshExpiresAt
            )
            saveStoredSession(storedSession)
        }
        screenState = .authenticated(meResponse.user)
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
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.12)) {
            activeDocument = AppDocumentDestination(kind: kind, id: id)
        }
    }

    func closeDocument() {
        // The detail container plays its own slide-out (dragOffsetX) before calling this, so the
        // actual removal is instant (.identity transition) — no second animation to fight it.
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

    func setHomeDisplayMode(_ mode: HomeDisplayMode) {
        guard chatFilterState.displayMode != mode else { return }

        activeDocument = nil
        isProfileOpen = false
        isChecklistOpen = false
        isChatFilterPresented = false
        updateChatFilterState(HomeChatFilterState(
            displayMode: mode,
            year: chatFilterState.year,
            months: chatFilterState.months,
            kinds: chatFilterState.kinds,
            hideCompleted: chatFilterState.hideCompleted,
            hideCancelled: chatFilterState.hideCancelled,
            orderMethodIDs: chatFilterState.orderMethodIDs,
            establishmentIDs: chatFilterState.establishmentIDs,
            statusIDs: chatFilterState.statusIDs
        ))
    }

    // MARK: - Управление токенами (проактивный рефреш)

    private enum RefreshOutcome {
        case success(AuthUser)
        case invalidSession   // refresh-токен реально невалиден → разлогин
        case transient        // сеть/временный сбой → не разлогиниваем, повторим позже
    }

    private var inFlightRefresh: Task<RefreshOutcome, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    private let refreshLeadTime: TimeInterval = 90          // обновляем за 90с до истечения
    private let refreshRetryDelay: TimeInterval = 20        // пауза перед повтором при сбое
    private let refreshFallbackInterval: TimeInterval = 1200 // если срок неизвестен

    /// Помечает пользователя авторизованным и запускает планировщик рефреша.
    private func setAuthenticated(_ user: AuthUser) {
        screenState = .authenticated(user)
        loadChatFilterState(for: user.userID)
        startTokenRefreshScheduler()
    }

    private func storedSession(from response: AuthResponse) -> StoredSession {
        StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            user: response.user,
            accessExpiresAt: HomeMessageDateParser.parse(response.accessExpiresAt),
            refreshExpiresAt: HomeMessageDateParser.parse(response.refreshExpiresAt)
        )
    }

    /// Обновляет токены, коалесируя одновременные вызовы в один сетевой запрос —
    /// иначе при ротации refresh-токена второй параллельный рефреш получил бы 401.
    @discardableResult
    private func refreshTokens() async -> RefreshOutcome {
        if let existing = inFlightRefresh {
            return await existing.value
        }
        let task = Task { await self.performRefreshOnce() }
        inFlightRefresh = task
        let outcome = await task.value
        inFlightRefresh = nil
        return outcome
    }

    private func performRefreshOnce() async -> RefreshOutcome {
        guard let stored = loadStoredSession() else { return .invalidSession }
        do {
            let response = try await client.refresh(refreshToken: stored.refreshToken)
            saveStoredSession(storedSession(from: response))
            // Обновим пользователя, не сбрасывая остальное состояние.
            if case .authenticated = screenState {
                screenState = .authenticated(response.user)
            }
            return .success(response.user)
        } catch let error as AuthServiceError {
            switch error {
            case let .backend(statusCode, message):
                if statusCode == 401 || statusCode == 403 || message.localizedCaseInsensitiveContains("деактивирован") {
                    return .invalidSession
                }
                return .transient
            case .transport, .invalidResponse:
                return .transient
            }
        } catch {
            return .transient
        }
    }

    private func handleInvalidSession(message: String) {
        stopTokenRefreshScheduler()
        clearStoredSession()
        authErrorMessage = message
        screenState = .login
        isProfileOpen = false
        isChecklistOpen = false
        activeDocument = nil
        isChatFilterPresented = false
        chatFilterState = HomeChatFilterState.default()
    }

    private func startTokenRefreshScheduler() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = Task { [weak self] in
            await self?.runTokenRefreshLoop()
        }
    }

    private func stopTokenRefreshScheduler() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
    }

    private func runTokenRefreshLoop() async {
        while !Task.isCancelled {
            guard case .authenticated = screenState, let stored = loadStoredSession() else { return }

            // Когда обновлять: за refreshLeadTime до истечения access-токена.
            let secondsUntilRefresh = stored.accessExpiresAt
                .map { max($0.timeIntervalSinceNow - refreshLeadTime, 0) }
                ?? 0   // срок неизвестен — обновим сразу, чтобы его получить

            if secondsUntilRefresh > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(secondsUntilRefresh, 6 * 3600) * 1_000_000_000))
                if Task.isCancelled { return }
            }

            guard case .authenticated = screenState else { return }

            switch await refreshTokens() {
            case .success:
                // Если бэкенд/парсер не дал срок — не крутимся вхолостую.
                if loadStoredSession()?.accessExpiresAt == nil {
                    try? await Task.sleep(nanoseconds: UInt64(refreshFallbackInterval * 1_000_000_000))
                }
            case .invalidSession:
                handleInvalidSession(message: "Сессия истекла, войдите снова")
                return
            case .transient:
                try? await Task.sleep(nanoseconds: UInt64(refreshRetryDelay * 1_000_000_000))
            }
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
                userCreatedAt: nil,
                userEstablishmentRoles: nil,
                userSections: nil
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
        // v2 — сброс старого сохранённого фильтра под новые дефолты («скрыть
        // выполненные/отмененные» включены по умолчанию). Старое состояние
        // игнорируется, все стартуют с default().
        "chat.filter-state.v2.\(userID)"
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
