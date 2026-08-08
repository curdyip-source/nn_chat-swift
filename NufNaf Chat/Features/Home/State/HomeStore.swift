//
//  HomeStore.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Combine
import Foundation

@MainActor
final class HomeStore: ObservableObject {
    @Published var messages: [HomeMessage] = [] {
        didSet { messagesRevision &+= 1 }
    }
    /// Счётчик изменений ленты. Производные списки во вью (фильтр чата, карточки СРМ)
    /// пересчитываются по нему: сравнивать сами массивы на каждом проходе тела дорого —
    /// сообщений сотни, а тело перевычисляется в том числе на каждом кадре свайпа.
    @Published private(set) var messagesRevision: Int = 0
    /// Счётчик изменений задач, сделанных ВНЕ экрана «Задачи» (из карточки заказа).
    /// Экран задач слушает его и перечитывает доску — иначе задача появлялась бы там
    /// только после перезахода.
    @Published private(set) var todoRevision: Int = 0
    @Published var messageDraft = ""
    @Published var isLoading = false
    @Published var isSendingMessage = false
    @Published var loadErrorMessage: String?
    @Published var isAttachmentMenuPresented = false
    @Published var activeComposer: HomeComposerKind?
    @Published var isMediaAlertPresented = false
    @Published var mediaAlertTitle = ""
    @Published var referenceData = HomeReferenceDataResponse(establishments: [], orderMethods: [], statuses: [], currencies: [])
    @Published var participants: [ChatParticipant] = []
    @Published private(set) var orderCommentReadRevision = 0

    /// Вызывается при SSE-событии `user_updated` (реалтайм-смена прав) с id затронутого
    /// пользователя. Проводится из HomeView, чтобы перечитать /me и применить доступ на лету.
    var onUserUpdated: ((Int) -> Void)?

    private let client: HomeAPIClient
    private let stream = MessageStreamClient()
    private let defaults = UserDefaults.standard
    private var localAttachmentPayloads: [Int: PendingAttachmentUpload] = [:]
    private var pendingBusinessDocumentCreations: [Int: PendingBusinessDocumentCreation] = [:]
    // Stable idempotency key per pending local message (text/attachment). Reused across automatic
    // and manual retries so the server discards a duplicate POST whose first response was lost.
    private var localMessageIdempotencyKeys: [Int: String] = [:]

    // Incremental sync state: local cache keyed per user + the server delta cursor.
    private var cache: MessageCache?
    private var syncCursor: String?
    private var isSyncing = false
    private var persistTask: Task<Void, Never>?

    private struct PendingAttachmentUpload {
        let data: Data
        let filename: String
        let mimeType: String
        let attachmentKind: String
        let localFileURL: URL
    }

    private enum PendingBusinessDocumentCreation {
        case order(HomeOrderCreateRequest, idempotencyKey: String)
        case inventory(HomeInventoryCreateRequest, idempotencyKey: String)
        case productRegistration(HomeProductRegistrationCreateRequest, idempotencyKey: String)

        var idempotencyKey: String {
            switch self {
            case let .order(_, key), let .inventory(_, key), let .productRegistration(_, key):
                return key
            }
        }
    }

    init(client: HomeAPIClient? = nil) {
        self.client = client ?? HomeAPIClient()
    }

    private func sortedMessages(_ items: [HomeMessage]) -> [HomeMessage] {
        items.sorted { lhs, rhs in
            switch (lhs.parsedCreatedAt, rhs.parsedCreatedAt) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate < rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.messageCreatedAt != rhs.messageCreatedAt {
                    return (lhs.messageCreatedAt ?? "") < (rhs.messageCreatedAt ?? "")
                }
                return lhs.id < rhs.id
            }
        }
    }

    private func mergeMessage(_ item: HomeMessage) {
        if let index = messages.firstIndex(where: { $0.id == item.id }) {
            messages[index] = item
        } else {
            messages.append(item)
        }
        messages = sortedMessages(messages)
    }

    private func nextLocalMessageID() -> Int {
        min(-1, (messages.map(\.id).min() ?? 0) - 1)
    }

    private func replaceMessage(localID: Int, with item: HomeMessage) {
        messages.removeAll { $0.id == localID }
        mergeMessage(item)
    }

    private func reconcileMessages(with loadedMessages: [HomeMessage]) -> [HomeMessage] {
        var reconciled = loadedMessages

        for localMessage in messages where localMessage.isLocalOnly {
            if reconciled.contains(where: { matchesServerMessage($0, for: localMessage) }) {
                continue
            }
            reconciled.append(localMessage)
        }

        return sortedMessages(reconciled)
    }

    private func matchesServerMessage(_ serverMessage: HomeMessage, for localMessage: HomeMessage) -> Bool {
        guard !serverMessage.isLocalOnly else { return false }
        guard serverMessage.messageOwnerUserID == localMessage.messageOwnerUserID else { return false }
        guard isCreatedNearInTime(serverMessage, localMessage) else { return false }

        if !localMessage.attachments.isEmpty {
            return matchesAttachmentMessage(serverMessage, localMessage: localMessage)
        }

        if localMessage.documentKind != nil {
            return matchesBusinessDocumentMessage(serverMessage, localMessage: localMessage)
        }

        return serverMessage.documentKind == nil
            && serverMessage.attachments.isEmpty
            && normalizedText(serverMessage.messageText) == normalizedText(localMessage.messageText)
    }

    private func matchesAttachmentMessage(_ serverMessage: HomeMessage, localMessage: HomeMessage) -> Bool {
        guard serverMessage.documentKind == nil else { return false }
        guard serverMessage.attachments.count == localMessage.attachments.count else { return false }
        guard let serverAttachment = serverMessage.attachments.first,
              let localAttachment = localMessage.attachments.first else {
            return false
        }

        return serverAttachment.attachmentKind == localAttachment.attachmentKind
            && normalizedText(serverAttachment.attachmentOriginalFilename) == normalizedText(localAttachment.attachmentOriginalFilename)
            && serverAttachment.attachmentMimeType == localAttachment.attachmentMimeType
            && serverAttachment.attachmentSizeBytes == localAttachment.attachmentSizeBytes
    }

    private func matchesBusinessDocumentMessage(_ serverMessage: HomeMessage, localMessage: HomeMessage) -> Bool {
        guard serverMessage.documentKind == localMessage.documentKind else { return false }

        switch localMessage.documentKind {
        case "order":
            return normalizedText(serverMessage.order?.orderCustomer) == normalizedText(documentCounterparty(for: localMessage))
                && normalizedText(serverMessage.order?.orderInfo) == normalizedText(documentInfo(for: localMessage))
        case "inventory":
            return normalizedText(serverMessage.inventory?.inventorySupplier) == normalizedText(documentCounterparty(for: localMessage))
        case "product_registration":
            return normalizedText(serverMessage.productRegistration?.productRegistrationSupplier) == normalizedText(documentCounterparty(for: localMessage))
        default:
            return false
        }
    }

    private func documentCounterparty(for message: HomeMessage) -> String {
        let components = message.messageText?
            .components(separatedBy: " | ")
            .map { normalizedText($0) } ?? []
        return components.first ?? ""
    }

    private func documentInfo(for message: HomeMessage) -> String {
        let components = message.messageText?
            .components(separatedBy: " | ")
            .map { normalizedText($0) } ?? []
        guard components.count > 1 else { return "" }
        return components.dropFirst().joined(separator: " | ")
    }

    private func normalizedText(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")) ?? ""
    }

    private func isCreatedNearInTime(_ lhs: HomeMessage, _ rhs: HomeMessage, tolerance: TimeInterval = 180) -> Bool {
        guard let leftDate = lhs.parsedCreatedAt,
              let rightDate = rhs.parsedCreatedAt else {
            return true
        }
        return abs(leftDate.timeIntervalSince(rightDate)) <= tolerance
    }

    private func scheduleConfirmationReloads(accessToken: String, localMessageID: Int) {
        Task { [weak self] in
            await self?.performConfirmationReloads(accessToken: accessToken, localMessageID: localMessageID)
        }
    }

    private func performConfirmationReloads(accessToken: String, localMessageID: Int) async {
        let delays: [UInt64] = [0, 700_000_000, 1_500_000_000, 3_000_000_000]
        for delay in delays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard messages.contains(where: { $0.id == localMessageID }) else { return }
            await reloadMessages(accessToken: accessToken)
            guard messages.contains(where: { $0.id == localMessageID }) else { return }
        }
    }

    private func updateLocalMessageState(messageID: Int, deliveryState: HomeMessageDeliveryState) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].deliveryState = deliveryState
        messages = sortedMessages(messages)
    }

    func discardLocalMessage(_ message: HomeMessage) {
        guard message.isLocalOnly else { return }
        messages.removeAll { $0.id == message.id }
        localAttachmentPayloads.removeValue(forKey: message.id)
        pendingBusinessDocumentCreations.removeValue(forKey: message.id)
        localMessageIdempotencyKeys.removeValue(forKey: message.id)
    }

    private func reloadMessagesInBackground(accessToken: String) {
        Task { [weak self] in
            await self?.reloadMessages(accessToken: accessToken)
        }
    }

    func load(accessToken: String?, userID: Int) async {
        configureCache(for: userID)

        guard let accessToken else {
            loadErrorMessage = "Сессия не найдена"
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Cache is already on screen (configureCache); pull only the delta since last sync.
        await syncDelta(accessToken: accessToken)

        do {
            referenceData = try await client.getReferenceData(accessToken: accessToken)
            AppVersionGate.shared.update(minBuild: referenceData.minSupportedIosBuild)
        } catch {
        }

        await loadParticipants(accessToken: accessToken)
    }

    /// Полный пере-синк ленты С НУЛЯ: сбрасываем курсор и текущие сообщения, затем тянем весь
    /// (уже отфильтрованный сервером по правам склада) фид заново. Нужно при реалтайм-смене прав —
    /// обычный дельта-синк НЕ убирает уже закешированные карточки, ставшие недоступными.
    func reloadFeedFromScratch(accessToken: String?) async {
        guard let accessToken, cache != nil else { return }
        syncCursor = nil
        messages = []
        persistCache()
        await syncDelta(accessToken: accessToken)
    }

    /// Point the store at this user's cache and show it immediately. No-op if already configured.
    private func configureCache(for userID: Int) {
        if cache?.userID == userID { return }
        let cache = MessageCache(userID: userID)
        self.cache = cache
        if let cached = cache.load() {
            syncCursor = cached.cursor
            messages = reconcileMessages(with: cached.messages)
        } else {
            syncCursor = nil
            messages = []
        }
    }

    /// Pull and apply all changes since the stored cursor, draining pagination.
    private func syncDelta(accessToken: String) async {
        guard cache != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            var cursor = syncCursor
            while true {
                let response = try await client.syncMessages(accessToken: accessToken, cursor: cursor)
                applySyncItems(response.items)
                cursor = response.cursor
                syncCursor = response.cursor
                if !response.hasMore { break }
            }
            loadErrorMessage = nil
            persistCache()
        } catch {
            // Keep the cached feed on screen; report the transport error like before.
            loadErrorMessage = error.localizedDescription
        }
    }

    private func applySyncItems(_ items: [HomeMessageSyncItem]) {
        guard !items.isEmpty else { return }
        var working = messages
        for item in items {
            switch item {
            case let .message(message):
                // Drop the optimistic local twin, if any, then upsert the server message.
                working.removeAll { $0.isLocalOnly && matchesServerMessage(message, for: $0) }
                if let index = working.firstIndex(where: { $0.id == message.id }) {
                    working[index] = message
                } else {
                    working.append(message)
                }
            case let .tombstone(id):
                working.removeAll { $0.id == id }
            }
        }
        messages = sortedMessages(working)
    }

    private func applyStreamEvent(_ event: MessageStreamEvent) {
        switch event.type {
        case "created", "updated":
            guard let message = event.message else { return }
            applySyncItems([.message(message)])
            schedulePersist()
        case "deleted":
            guard let id = event.messageID else { return }
            applySyncItems([.tombstone(id: id)])
            schedulePersist()
        case "user_updated":
            // Реалтайм-смена прав/разделов/статуса. Пробрасываем наверх (сверку с текущим
            // пользователем и перечитывание /me делает HomeView).
            if let userID = event.subjectUserID {
                onUserUpdated?(userID)
            }
        case "app_config_updated":
            // Реалтайм-смена порога форс-апдейта из «Админки» — применяем сразу.
            if let minBuild = event.minSupportedIosBuild {
                AppVersionGate.shared.update(minBuild: minBuild)
            }
        default:
            break
        }
    }

    private func persistCache() {
        guard let cache else { return }
        cache.save(CachedChatFeed(messages: messages.filter { !$0.isLocalOnly }, cursor: syncCursor))
    }

    /// Coalesce frequent SSE-driven writes: persist at most once per short window.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.persistCache()
        }
    }

    /// Long-lived realtime loop: catch up via delta sync, then consume SSE until the connection
    /// drops, then back off and reconnect. Cancelled by the owning SwiftUI `.task`.
    func runRealtime(accessToken: String?) async {
        guard let accessToken else { return }
        while !Task.isCancelled {
            await syncDelta(accessToken: accessToken)
            do {
                for try await payload in stream.events(accessToken: accessToken) {
                    if Task.isCancelled { return }
                    // Decode here (main actor) — the model's Decodable conformance is main-actor isolated.
                    if let event = try? JSONDecoder().decode(MessageStreamEvent.self, from: payload) {
                        applyStreamEvent(event)
                    }
                }
            } catch {
                // Connection dropped — fall through to back off and reconnect.
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    func loadParticipants(accessToken: String?) async {
        guard let accessToken else { return }
        do {
            participants = try await client.fetchParticipants(accessToken: accessToken)
        } catch {
        }
    }

    func reloadMessages(accessToken: String?) async {
        guard let accessToken else { return }
        await syncDelta(accessToken: accessToken)
    }

    func sendMessage(accessToken: String?) async {
        _ = accessToken
    }

    func sendMessage(accessToken: String?, currentUser: AuthUser, text: String, clearDraft: Bool, mentionedUserIDs: [Int] = []) async {
        guard let accessToken else { return }
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        let localMessageID = nextLocalMessageID()
        let localMessage = HomeMessage.makeLocalTextMessage(
            id: localMessageID,
            text: normalizedText,
            user: currentUser,
            deliveryState: .pending
        )

        if clearDraft {
            messageDraft = ""
        }
        mergeMessage(localMessage)

        let idempotencyKey = idempotencyKey(for: localMessageID)
        do {
            let createdMessage = try await client.sendMessage(accessToken: accessToken, text: normalizedText, mentionedUserIDs: mentionedUserIDs, idempotencyKey: idempotencyKey)
            replaceMessage(localID: localMessageID, with: createdMessage)
            localMessageIdempotencyKeys.removeValue(forKey: localMessageID)
            reloadMessagesInBackground(accessToken: accessToken)
        } catch {
            updateLocalMessageState(messageID: localMessageID, deliveryState: .failed)
            if error.isPermissionDenied {
                AppAlertCenter.shared.showPermissionDenied()
            }
        }
    }

    /// Returns the stable idempotency key for a pending local message, creating one on first use.
    /// Reusing it across retries lets the server collapse a re-sent create into the original.
    private func idempotencyKey(for localMessageID: Int) -> String {
        if let existing = localMessageIdempotencyKeys[localMessageID] {
            return existing
        }
        let key = UUID().uuidString
        localMessageIdempotencyKeys[localMessageID] = key
        return key
    }

    func retryFailedMessage(accessToken: String?, currentUser: AuthUser, message: HomeMessage) async {
        guard let accessToken, message.canRetryDelivery else { return }

        if !message.attachments.isEmpty {
            guard let payload = localAttachmentPayloads[message.id] else { return }
            updateLocalMessageState(messageID: message.id, deliveryState: .pending)
            await finishSendingAttachment(accessToken: accessToken, localMessageID: message.id, payload: payload)
            return
        }

        if let creation = pendingBusinessDocumentCreations[message.id] {
            updateLocalMessageState(messageID: message.id, deliveryState: .pending)
            await finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: message.id, creation: creation)
            return
        }

        guard let messageText = message.messageText else { return }

        updateLocalMessageState(messageID: message.id, deliveryState: .pending)

        do {
            let createdMessage = try await client.sendMessage(accessToken: accessToken, text: messageText, idempotencyKey: idempotencyKey(for: message.id))
            replaceMessage(localID: message.id, with: createdMessage)
            localMessageIdempotencyKeys.removeValue(forKey: message.id)
            reloadMessagesInBackground(accessToken: accessToken)
        } catch {
            updateLocalMessageState(messageID: message.id, deliveryState: .failed)
            if error.isPermissionDenied {
                AppAlertCenter.shared.showPermissionDenied()
            }
        }
    }

    func updateMessage(accessToken: String?, messageID: Int, text: String) async throws -> HomeMessage {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let updatedMessage = try await client.updateMessage(accessToken: accessToken, messageID: messageID, text: text)
        mergeMessage(updatedMessage)
        reloadMessagesInBackground(accessToken: accessToken)
        return updatedMessage
    }

    func deleteMessage(accessToken: String?, message: HomeMessage) async throws {
        if message.isLocalOnly {
            discardLocalMessage(message)
            return
        }

        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }

        messages.removeAll { $0.id == message.id }

        do {
            try await client.deleteMessage(accessToken: accessToken, messageID: message.id)
        } catch {
            mergeMessage(message)
            throw error
        }

        reloadMessagesInBackground(accessToken: accessToken)
    }

    func sendAttachment(accessToken: String?, currentUser: AuthUser, data: Data, filename: String, mimeType: String, attachmentKind: String) async throws -> HomeMessage {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }

        let localFileURL = try persistAttachmentToTemporaryURL(data: data, filename: filename)
        let localMessageID = nextLocalMessageID()
        let localAttachment = HomeMessageAttachment.makeLocal(
            id: localMessageID,
            kind: attachmentKind,
            filename: filename,
            mimeType: mimeType,
            sizeBytes: data.count,
            localFileURL: localFileURL
        )
        let localMessage = HomeMessage.makeLocalAttachmentMessage(
            id: localMessageID,
            attachment: localAttachment,
            user: currentUser,
            deliveryState: .pending
        )
        let payload = PendingAttachmentUpload(
            data: data,
            filename: filename,
            mimeType: mimeType,
            attachmentKind: attachmentKind,
            localFileURL: localFileURL
        )

        localAttachmentPayloads[localMessageID] = payload
        mergeMessage(localMessage)

        Task { [weak self] in
            await self?.finishSendingAttachment(accessToken: accessToken, localMessageID: localMessageID, payload: payload)
        }

        return localMessage
    }

    private func finishSendingAttachment(accessToken: String, localMessageID: Int, payload: PendingAttachmentUpload) async {
        do {
            let uploadedAttachment = try await client.uploadMessageAttachment(
                accessToken: accessToken,
                data: payload.data,
                filename: payload.filename,
                mimeType: payload.mimeType,
                attachmentKind: payload.attachmentKind
            )
            let message = try await client.sendAttachmentMessage(
                accessToken: accessToken,
                attachments: [
                    HomeMessageAttachmentCreateRequest(
                        attachmentKind: uploadedAttachment.attachmentKind,
                        attachmentOriginalFilename: uploadedAttachment.attachmentOriginalFilename,
                        attachmentMimeType: uploadedAttachment.attachmentMimeType,
                        attachmentStorageKey: uploadedAttachment.attachmentStorageKey,
                        attachmentSizeBytes: uploadedAttachment.attachmentSizeBytes
                    )
                ],
                idempotencyKey: idempotencyKey(for: localMessageID)
            )
            localAttachmentPayloads.removeValue(forKey: localMessageID)
            localMessageIdempotencyKeys.removeValue(forKey: localMessageID)
            replaceMessage(localID: localMessageID, with: message)
            scheduleConfirmationReloads(accessToken: accessToken, localMessageID: message.id)
        } catch {
            updateLocalMessageState(messageID: localMessageID, deliveryState: .failed)
            if error.isPermissionDenied {
                AppAlertCenter.shared.showPermissionDenied()
            }
        }
    }

    private func persistAttachmentToTemporaryURL(data: Data, filename: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("chat-local-attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let sanitizedName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = sanitizedName.isEmpty ? "attachment" : sanitizedName
        let targetURL = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(finalName)")
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    func downloadAttachmentToTemporaryURL(_ attachment: HomeMessageAttachment) async throws -> URL {
        guard let url = attachment.mediaURL else {
            throw AuthServiceError.invalidResponse
        }

        let downloaded = try await client.downloadAttachment(from: url)
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("chat-attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let sanitizedFilename = attachment.attachmentOriginalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL = directoryURL.appendingPathComponent(sanitizedFilename.isEmpty ? "attachment" : sanitizedFilename)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try downloaded.data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    func presentMediaPlaceholder(kind: String) {
        mediaAlertTitle = kind
        isMediaAlertPresented = true
    }

    func searchProducts(accessToken: String?, query: String) async -> [HomeProduct] {
        guard let accessToken, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        do {
            return try await client.searchProducts(accessToken: accessToken, query: query)
        } catch {
            return []
        }
    }

    func searchContacts(accessToken: String?, contactType: String, query: String) async -> [HomeContact] {
        guard let accessToken else {
            return []
        }
        do {
            return try await client.searchContacts(accessToken: accessToken, contactType: contactType, query: query)
        } catch {
            return []
        }
    }

    // MARK: - СДЭК

    func searchCdekCities(accessToken: String?, query: String) async -> [CdekCity] {
        guard let accessToken, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }
        do { return try await client.suggestCdekCities(accessToken: accessToken, query: query) } catch { return [] }
    }

    func fetchCdekDeliveryPoints(accessToken: String?, cityCode: Int, query: String?) async -> [CdekPvz] {
        guard let accessToken else { return [] }
        do { return try await client.fetchCdekDeliveryPoints(accessToken: accessToken, cityCode: cityCode, query: query) } catch { return [] }
    }

    func fetchCdekTariffs(accessToken: String?, toCode: Int, weight: Int, fromCode: Int? = nil) async -> [CdekTariff] {
        guard let accessToken else { return [] }
        do { return try await client.fetchCdekTariffs(accessToken: accessToken, toCode: toCode, weight: weight, fromCode: fromCode) } catch { return [] }
    }

    func createCdekWaybill(accessToken: String?, orderID: Int, request: CdekWaybillCreateRequest) async throws -> HomeOrderCdek {
        guard let accessToken else { throw AuthServiceError.transport("Сессия не найдена") }
        return try await client.createCdekWaybill(accessToken: accessToken, orderID: orderID, request: request)
    }

    func cdekWaybillStatus(accessToken: String?, orderID: Int) async throws -> HomeOrderCdek {
        guard let accessToken else { throw AuthServiceError.transport("Сессия не найдена") }
        return try await client.cdekWaybillStatus(accessToken: accessToken, orderID: orderID)
    }

    func cdekPrefill(accessToken: String?, customer: String) async -> CdekPrefill? {
        guard let accessToken, !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { return try await client.cdekPrefill(accessToken: accessToken, customer: customer) } catch { return nil }
    }

    func deleteCdekWaybill(accessToken: String?, orderID: Int) async throws -> HomeOrderCdek {
        guard let accessToken else { throw AuthServiceError.transport("Сессия не найдена") }
        return try await client.deleteCdekWaybill(accessToken: accessToken, orderID: orderID)
    }

    func cdekDefaults(accessToken: String?) async -> CdekOriginDefault? {
        guard let accessToken else { return nil }
        do { return try await client.cdekDefaults(accessToken: accessToken) } catch { return nil }
    }

    func createProduct(accessToken: String?, article: String, name: String, costUSD: String) async throws -> HomeProduct {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.createProduct(
            accessToken: accessToken,
            request: HomeProductCreateRequest(
                productArticle: article,
                productName: name,
                productCostUSD: costUSD
            )
        )
    }

    func fetchOrder(accessToken: String?, orderID: Int) async throws -> HomeOrder {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.getOrder(accessToken: accessToken, orderID: orderID)
    }

    /// The order already embedded in the chat feed cache, if any — used to render a detail view
    /// instantly while the fresh copy loads, so content animates in with the open transition
    /// instead of popping in after the network fetch.
    func cachedOrder(orderID: Int) -> HomeOrder? {
        messages.first(where: { $0.order?.id == orderID })?.order
    }

    func updateOrder(accessToken: String?, orderID: Int, request: HomeOrderUpdateRequest) async throws -> HomeOrder {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let order = try await client.updateOrder(accessToken: accessToken, orderID: orderID, request: request)
        await reloadMessages(accessToken: accessToken)
        return order
    }

    func addOrderComment(accessToken: String?, orderID: Int, text: String, mentionedUserIDs: [Int] = []) async throws -> HomeOrderComment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let comment = try await client.addOrderComment(accessToken: accessToken, orderID: orderID, text: text, mentionedUserIDs: mentionedUserIDs, idempotencyKey: UUID().uuidString)
        reloadMessagesInBackground(accessToken: accessToken)
        return comment
    }

    func addOrderComment(accessToken: String?, orderID: Int, text: String?, attachments: [HomeMessageAttachmentCreateRequest], mentionedUserIDs: [Int] = []) async throws -> HomeOrderComment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let comment = try await client.addOrderComment(accessToken: accessToken, orderID: orderID, text: text, attachments: attachments, mentionedUserIDs: mentionedUserIDs, idempotencyKey: UUID().uuidString)
        reloadMessagesInBackground(accessToken: accessToken)
        return comment
    }

    func updateOrderComment(accessToken: String?, orderID: Int, commentID: Int, text: String, mentionedUserIDs: [Int] = []) async throws -> HomeOrderComment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let updated = try await client.updateOrderComment(accessToken: accessToken, orderID: orderID, commentID: commentID, text: text, mentionedUserIDs: mentionedUserIDs)
        reloadMessagesInBackground(accessToken: accessToken)
        return updated
    }

    func setOrderCommentPinned(accessToken: String?, orderID: Int, commentID: Int, pinned: Bool) async throws -> HomeOrderComment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let updated = try await client.setOrderCommentPinned(accessToken: accessToken, orderID: orderID, commentID: commentID, pinned: pinned)
        // Закреплённое сообщение видно в карточке заказа в списках СРМ — обновляем ленту,
        // как после правки комментария.
        reloadMessagesInBackground(accessToken: accessToken)
        return updated
    }

    func deleteOrderComment(accessToken: String?, orderID: Int, commentID: Int) async throws {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        try await client.deleteOrderComment(accessToken: accessToken, orderID: orderID, commentID: commentID)
        // Карточка заказа перечитается по SSE-дельте (notify_order_changed на бэке),
        // но подстрахуемся фоновой пересинхронизацией — как в deleteMessage.
        reloadMessagesInBackground(accessToken: accessToken)
    }

    // MARK: - Задачи заказа
    // Тудулист живёт своим стором, но карточка заказа умеет вести свои задачи сама:
    // после каждой операции заказ перечитывается, а лента обновляется в фоне.

    /// Создать задачу заказа целиком из формы: название, заметка, сроки и
    /// ответственные уходят одним запросом.
    func createOrderTodo(accessToken: String?, orderID: Int, draft: TodoItem) async throws {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let request = TodoCreateRequest(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            listID: draft.listID,
            orderID: orderID,
            assigneeUserIDs: draft.assignees.map(\.id),
            note: draft.note,
            doAt: draft.doAt,
            deadlineAt: draft.deadlineAt
        )
        _ = try await client.createTodo(accessToken: accessToken, request: request)
        todoRevision &+= 1
        reloadMessagesInBackground(accessToken: accessToken)
    }

    func setTodoCompleted(accessToken: String?, todoID: Int, completed: Bool) async throws {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        _ = try await client.setTodoCompleted(accessToken: accessToken, todoID: todoID, completed: completed)
        todoRevision &+= 1
        reloadMessagesInBackground(accessToken: accessToken)
    }

    func archiveTodo(accessToken: String?, todoID: Int) async throws {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        _ = try await client.setTodoArchived(accessToken: accessToken, todoID: todoID, archived: true)
        todoRevision &+= 1
        reloadMessagesInBackground(accessToken: accessToken)
    }

    func saveTodo(accessToken: String?, item: TodoItem) async throws {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let request = TodoUpdateRequest(
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
            listID: item.listID,
            orderID: item.orderID,
            assigneeUserIDs: item.assignees.map(\.id),
            note: item.note,
            doAt: item.doAt,
            deadlineAt: item.deadlineAt,
            someday: item.someday,
            tags: item.tags,
            subtasks: item.subtasks.map { TodoSubtaskRequest(title: $0.title, done: $0.done) }
        )
        _ = try await client.updateTodo(accessToken: accessToken, todoID: item.id, request: request)
        todoRevision &+= 1
        reloadMessagesInBackground(accessToken: accessToken)
    }

    func deleteTodo(accessToken: String?, todoID: Int) async throws {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        try await client.deleteTodo(accessToken: accessToken, todoID: todoID)
        todoRevision &+= 1
        reloadMessagesInBackground(accessToken: accessToken)
    }

    func uploadOrderCommentAttachment(accessToken: String?, data: Data, filename: String, mimeType: String, attachmentKind: String) async throws -> HomeUploadedMessageAttachment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.uploadMessageAttachment(
            accessToken: accessToken,
            data: data,
            filename: filename,
            mimeType: mimeType,
            attachmentKind: attachmentKind
        )
    }

    func persistOrderCommentAttachmentToTemporaryURL(data: Data, filename: String) throws -> URL {
        try persistAttachmentToTemporaryURL(data: data, filename: filename)
    }

    func downloadOrderCommentAttachmentToTemporaryURL(_ attachment: HomeOrderCommentAttachment) async throws -> URL {
        guard let url = attachment.mediaURL else {
            throw AuthServiceError.invalidResponse
        }

        let downloaded = try await client.downloadAttachment(from: url)
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("order-comment-attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let sanitizedFilename = attachment.attachmentOriginalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL = directoryURL.appendingPathComponent(sanitizedFilename.isEmpty ? "attachment" : sanitizedFilename)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try downloaded.data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    func unreadOrderCommentCount(for order: HomeOrder, currentUserID: Int) -> Int {
        let lastReadID = lastReadOrderCommentID(orderID: order.id, userID: currentUserID)
        return order.comments.reduce(into: 0) { result, comment in
            guard comment.ownerUserID != currentUserID else { return }
            guard comment.id > lastReadID else { return }
            result += 1
        }
    }

    func markOrderCommentsRead(orderID: Int, comments: [HomeOrderComment], userID: Int) {
        let latestID = comments.map(\ .id).max() ?? 0
        let key = orderCommentsReadKey(orderID: orderID, userID: userID)
        if latestID > defaults.integer(forKey: key) {
            defaults.set(latestID, forKey: key)
            orderCommentReadRevision += 1
        }
    }

    private func lastReadOrderCommentID(orderID: Int, userID: Int) -> Int {
        defaults.integer(forKey: orderCommentsReadKey(orderID: orderID, userID: userID))
    }

    private func orderCommentsReadKey(orderID: Int, userID: Int) -> String {
        "home.order-comments.last-read.\(userID).\(orderID)"
    }

    func updateOrderStatus(accessToken: String?, order: HomeOrder, statusID: Int, cancelAllItems: Bool = false) async throws -> HomeOrder {
        // При отмене заказа с cancelAllItems=true всем товарам проставляем статус «Отменен».
        let cancelledItemStatusID = cancelAllItems ? cancelledOrderItemStatusID() : nil
        return try await updateOrder(
            accessToken: accessToken,
            orderID: order.id,
            request: HomeOrderUpdateRequest(
                orderEstablishmentID: order.orderEstablishmentID,
                orderMethodID: order.orderMethodID,
                orderSubMethod: order.orderSubMethod,
                orderContactMethod: order.orderContactMethod,
                orderSalesChannel: order.orderSalesChannel,
                orderCustomer: order.orderCustomer,
                orderInfo: order.orderInfo,
                orderStatusID: statusID,
                items: order.items.map {
                    HomeOrderItemCreateRequest(
                        productID: $0.orderItemProductID,
                        productArticle: $0.orderItemArticle,
                        productName: $0.orderItemName,
                        orderItemQuantity: $0.orderItemQuantity,
                        orderItemPrice: $0.orderItemPrice,
                        orderItemStatusID: cancelledItemStatusID ?? $0.orderItemStatusID,
                        orderItemNote: $0.orderItemNote,
                        orderItemSourceEstablishmentID: $0.orderItemSourceEstablishmentID,
                        orderItemDestinationEstablishmentID: $0.orderItemDestinationEstablishmentID,
                        orderItemCurrencyID: $0.orderItemCurrencyID,
                        orderItemCheckpointStarted: $0.orderItemCheckpointStarted,
                        orderItemCheckpointCompleted: $0.orderItemCheckpointCompleted
                    )
                }
            )
        )
    }

    /// Отметить заказ оплаченным (или снять отметку) — кнопка у «Итого» в карточке.
    func updateOrderPayment(accessToken: String?, order: HomeOrder, paid: Bool) async throws -> HomeOrder {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let updated = try await client.updateOrderPayment(accessToken: accessToken, orderID: order.id, paid: paid)
        // Карточка перечитается по SSE-дельте (notify_order_changed на бэке);
        // пересинхронизация — чтобы список обновился сразу, как при смене статуса.
        await reloadMessages(accessToken: accessToken)
        return updated
    }

    /// id статуса товара «Отменен» (order_products), если есть в справочнике.
    func cancelledOrderItemStatusID() -> Int? {
        referenceData.statuses.first { $0.statusType == "order_products" && $0.statusStatus == "Отменен" }?.id
    }

    /// Имя статуса ЗАКАЗА по id (orders).
    func orderStatusName(_ statusID: Int?) -> String? {
        guard let statusID else { return nil }
        return referenceData.statuses.first { $0.statusType == "orders" && $0.id == statusID }?.statusStatus
    }

    /// true, если в заказе есть хотя бы один товар не в статусе «Отменен» (значит есть что
    /// отменять — показываем диалог при переводе заказа в «Отменен»).
    func orderHasNonCancelledItems(_ order: HomeOrder) -> Bool {
        order.items.contains { orderItemStatusName($0.orderItemStatusID) != "Отменен" }
    }

    // MARK: - Сборка/отгрузка: отменённые позиции и перевод заказа в «На сборку»

    /// Статусы товара, считающиеся отменёнными: не участвуют в сборке и не влияют на
    /// статус заказа (не показываются в отгрузке, но остаются в карточке заказа).
    static let cancelledItemStatusNames: Set<String> = ["Отменен", "Не будет"]
    /// Статусы позиции, которая реально уходит в отгрузку сейчас: «В наличии» — надо
    /// собрать, «Собрано» — склад уже собрал, «Упаковано» — сборщик уже упаковал.
    static let collectableItemStatusNames: Set<String> = ["В наличии", "Собрано", "Упаковано"]
    /// Статусы товара, при которых заказ можно перевести в «На сборку».
    private static let assemblyReadyItemStatusNames: Set<String> = ["В наличии", "Собрано", "Упаковано", "Отменен", "Не будет"]

    func orderItemStatusName(_ statusID: Int?) -> String? {
        guard let statusID else { return nil }
        return referenceData.statuses.first { $0.statusType == "order_products" && $0.id == statusID }?.statusStatus
    }

    func isCancelledOrderItem(_ item: HomeOrderItem) -> Bool {
        guard let name = orderItemStatusName(item.orderItemStatusID) else { return false }
        return Self.cancelledItemStatusNames.contains(name)
    }

    /// true, если все товары готовы к сборке («В наличии»/«Собрано» либо отменены)
    /// И есть хотя бы один собираемый («В наличии»/«Собрано», иначе собирать нечего) —
    /// тогда заказ можно перевести в «На сборку».
    func canMoveOrderToAssembly(_ order: HomeOrder) -> Bool {
        guard !order.items.isEmpty else { return false }
        let allResolved = order.items.allSatisfy { item in
            guard let name = orderItemStatusName(item.orderItemStatusID) else { return false }
            return Self.assemblyReadyItemStatusNames.contains(name)
        }
        return allResolved && orderHasCollectableItems(order)
    }

    /// Перевод заказа в «На сборку»: гейт (все товары в наличии/отменены) + конверсия
    /// «Не будет» → «Отменен», атомарно со сменой статуса заказа. Кидает при непройденном
    /// гейте или отсутствии статуса «Отменен».
    func moveOrderToAssembly(accessToken: String?, order: HomeOrder, assemblyStatusID: Int) async throws -> HomeOrder {
        let allResolved = !order.items.isEmpty && order.items.allSatisfy { item in
            guard let name = orderItemStatusName(item.orderItemStatusID) else { return false }
            return Self.assemblyReadyItemStatusNames.contains(name)
        }
        guard allResolved else {
            throw AuthServiceError.transport("В «На сборку» можно перевести, только когда все товары «В наличии»/«Собрано» (или отменены: «Не будет»/«Отменен»).")
        }
        guard orderHasCollectableItems(order) else {
            throw AuthServiceError.transport("Нельзя перевести в «На сборку»: нет товаров для сборки — все позиции отменены.")
        }
        guard let cancelledStatusID = referenceData.statuses.first(where: {
            $0.statusType == "order_products" && $0.statusStatus == "Отменен"
        })?.id else {
            throw AuthServiceError.transport("Не найден статус товара «Отменен»")
        }

        return try await updateOrder(
            accessToken: accessToken,
            orderID: order.id,
            request: HomeOrderUpdateRequest(
                orderEstablishmentID: order.orderEstablishmentID,
                orderMethodID: order.orderMethodID,
                orderSubMethod: order.orderSubMethod,
                orderContactMethod: order.orderContactMethod,
                orderSalesChannel: order.orderSalesChannel,
                orderCustomer: order.orderCustomer,
                orderInfo: order.orderInfo,
                orderStatusID: assemblyStatusID,
                items: order.items.map { item in
                    let convertedStatusID = orderItemStatusName(item.orderItemStatusID) == "Не будет"
                        ? cancelledStatusID
                        : item.orderItemStatusID
                    return HomeOrderItemCreateRequest(
                        productID: item.orderItemProductID,
                        productArticle: item.orderItemArticle,
                        productName: item.orderItemName,
                        orderItemQuantity: item.orderItemQuantity,
                        orderItemPrice: item.orderItemPrice,
                        orderItemStatusID: convertedStatusID,
                        orderItemSupplier: item.orderItemSupplier,
                        orderItemNote: item.orderItemNote,
                        orderItemSourceEstablishmentID: item.orderItemSourceEstablishmentID,
                        orderItemDestinationEstablishmentID: item.orderItemDestinationEstablishmentID,
                        orderItemCurrencyID: item.orderItemCurrencyID,
                        orderItemCheckpointStarted: item.orderItemCheckpointStarted,
                        orderItemCheckpointCompleted: item.orderItemCheckpointCompleted
                    )
                }
            )
        )
    }

    /// Есть ли позиции, готовые к отгрузке сейчас («В наличии» или уже «Собрано»).
    func orderHasCollectableItems(_ order: HomeOrder) -> Bool {
        order.items.contains { item in
            guard let name = orderItemStatusName(item.orderItemStatusID) else { return false }
            return Self.collectableItemStatusNames.contains(name)
        }
    }

    /// Есть ли ожидаемые товары (не готовы к сборке и не отменены) — для предложения сплита.
    func orderHasPendingItems(_ order: HomeOrder) -> Bool {
        order.items.contains { item in
            guard let name = orderItemStatusName(item.orderItemStatusID) else { return true }
            return !Self.assemblyReadyItemStatusNames.contains(name)
        }
    }

    /// Частичная отгрузка: бэкенд атомарно оставляет «В наличии» в этом заказе (→ «На
    /// сборку»), а остальное (ожидаемые + отменённые) переносит в новый заказ-дубль со
    /// статусом исходного. Оба заказа синхронизируются realtime (SSE + дельта-синк);
    /// возвращаем обновлённый исходный заказ.
    func splitOrderForAssembly(accessToken: String?, order: HomeOrder) async throws -> HomeOrder {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        guard orderHasCollectableItems(order) else {
            throw AuthServiceError.transport("Нет товаров для сборки")
        }
        let response = try await client.splitOrder(accessToken: accessToken, orderID: order.id)
        return response.order
    }

    func fetchInventory(accessToken: String?, inventoryID: Int) async throws -> HomeInventory {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.getInventory(accessToken: accessToken, inventoryID: inventoryID)
    }

    func updateInventoryStatus(accessToken: String?, inventoryID: Int, statusID: Int) async throws -> HomeInventory {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let inventory = try await client.updateInventoryStatus(
            accessToken: accessToken,
            inventoryID: inventoryID,
            request: HomeInventoryStatusUpdateRequest(inventoryStatusID: statusID)
        )
        await reloadMessages(accessToken: accessToken)
        return inventory
    }

    func fetchProductRegistration(accessToken: String?, productRegistrationID: Int) async throws -> HomeProductRegistration {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.getProductRegistration(accessToken: accessToken, productRegistrationID: productRegistrationID)
    }

    func updateProductRegistrationStatus(accessToken: String?, productRegistrationID: Int, statusID: Int) async throws -> HomeProductRegistration {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let registration = try await client.updateProductRegistrationStatus(
            accessToken: accessToken,
            productRegistrationID: productRegistrationID,
            request: HomeProductRegistrationStatusUpdateRequest(productRegistrationStatusID: statusID)
        )
        await reloadMessages(accessToken: accessToken)
        return registration
    }

    func saveProfile(accessToken: String?, request: HomeProfileUpdateRequest) async throws -> AuthUser {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.updateProfile(accessToken: accessToken, request: request)
    }

    func uploadProfilePhoto(accessToken: String?, jpegData: Data) async throws -> AuthUser {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.uploadProfilePhoto(accessToken: accessToken, jpegData: jpegData)
    }

    func submitComposer(kind: HomeComposerKind, accessToken: String?, currentUser: AuthUser, establishmentID: Int, orderMethodID: Int?, orderSubMethod: String?, orderContactMethod: String?, orderSalesChannel: String? = nil, counterpartyName: String, info: String, saveContact: Bool, orderStatusID: Int? = nil, defaultOrderItemStatusID: Int? = nil, cdek: HomeOrderCdekRequest? = nil, items: [HomeComposerItemDraft]) async {
        guard let accessToken else { return }
        let normalizedItems = items.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !normalizedItems.isEmpty else { return }

        let localMessageID = nextLocalMessageID()
        let idempotencyKey = UUID().uuidString

        switch kind {
        case .order:
            let request = HomeOrderCreateRequest(
                orderEstablishmentID: establishmentID,
                orderMethodID: orderMethodID ?? referenceData.orderMethods.first?.id ?? 1,
                orderSubMethod: orderSubMethod,
                orderContactMethod: orderContactMethod,
                orderSalesChannel: orderSalesChannel,
                orderCustomer: counterpartyName,
                orderInfo: info,
                orderStatusID: orderStatusID,
                saveContact: saveContact,
                cdek: cdek,
                items: normalizedItems.map {
                    HomeOrderItemCreateRequest(
                        productID: $0.productID,
                        productArticle: $0.productID == nil ? $0.article : nil,
                        productName: $0.productID == nil ? $0.name : nil,
                        orderItemQuantity: $0.quantity,
                        orderItemPrice: $0.price,
                        orderItemStatusID: $0.statusID ?? defaultOrderItemStatusID,
                        orderItemCurrencyID: $0.currencyID
                    )
                }
            )
            let localMessage = makeLocalBusinessDocumentMessage(
                id: localMessageID,
                currentUser: currentUser,
                kind: .order,
                establishmentID: establishmentID,
                counterpartyName: counterpartyName,
                info: info
            )
            let creation: PendingBusinessDocumentCreation = .order(request, idempotencyKey: idempotencyKey)
            pendingBusinessDocumentCreations[localMessageID] = creation
            mergeMessage(localMessage)
            Task { [weak self] in
                await self?.finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: localMessageID, creation: creation)
            }
        case .inventory:
            let request = HomeInventoryCreateRequest(
                inventoryEstablishmentID: establishmentID,
                inventorySupplier: counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : counterpartyName,
                saveContact: saveContact,
                items: normalizedItems.map {
                    HomeInventoryItemCreateRequest(
                        productID: $0.productID,
                        productArticle: $0.productID == nil ? $0.article : nil,
                        productName: $0.productID == nil ? $0.name : nil,
                        inventoryItemQuantity: $0.quantity,
                        inventoryItemCost: $0.price,
                        inventoryItemCurrencyID: $0.currencyID
                    )
                }
            )
            let localMessage = makeLocalBusinessDocumentMessage(
                id: localMessageID,
                currentUser: currentUser,
                kind: .inventory,
                establishmentID: establishmentID,
                counterpartyName: counterpartyName,
                info: info
            )
            let creation: PendingBusinessDocumentCreation = .inventory(request, idempotencyKey: idempotencyKey)
            pendingBusinessDocumentCreations[localMessageID] = creation
            mergeMessage(localMessage)
            Task { [weak self] in
                await self?.finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: localMessageID, creation: creation)
            }
        case .productRegistration:
            let request = HomeProductRegistrationCreateRequest(
                productRegistrationEstablishmentID: establishmentID,
                productRegistrationSupplier: counterpartyName,
                saveContact: saveContact,
                items: normalizedItems.map {
                    HomeProductRegistrationItemCreateRequest(
                        productID: $0.productID,
                        productArticle: $0.productID == nil ? $0.article : nil,
                        productName: $0.productID == nil ? $0.name : nil,
                        productRegistrationItemQuantity: $0.quantity,
                        productRegistrationItemCost: $0.price,
                        productRegistrationItemCurrencyID: $0.currencyID
                    )
                }
            )
            let localMessage = makeLocalBusinessDocumentMessage(
                id: localMessageID,
                currentUser: currentUser,
                kind: .productRegistration,
                establishmentID: establishmentID,
                counterpartyName: counterpartyName,
                info: info
            )
            let creation: PendingBusinessDocumentCreation = .productRegistration(request, idempotencyKey: idempotencyKey)
            pendingBusinessDocumentCreations[localMessageID] = creation
            mergeMessage(localMessage)
            Task { [weak self] in
                await self?.finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: localMessageID, creation: creation)
            }
        }
    }

    private func finishBusinessDocumentCreation(accessToken: String, localMessageID: Int, creation: PendingBusinessDocumentCreation) async {
        do {
            switch creation {
            case let .order(request, idempotencyKey):
                try await client.createOrder(accessToken: accessToken, request: request, idempotencyKey: idempotencyKey)
            case let .inventory(request, idempotencyKey):
                try await client.createInventory(accessToken: accessToken, request: request, idempotencyKey: idempotencyKey)
            case let .productRegistration(request, idempotencyKey):
                try await client.createProductRegistration(accessToken: accessToken, request: request, idempotencyKey: idempotencyKey)
            }
            pendingBusinessDocumentCreations.removeValue(forKey: localMessageID)
            updateLocalMessageState(messageID: localMessageID, deliveryState: .sent)
            scheduleConfirmationReloads(accessToken: accessToken, localMessageID: localMessageID)
        } catch {
            if error.isPermissionDenied {
                // No rights to create this document — don't leave a "failed" card
                // stuck in the chat; drop the optimistic card and show the global
                // permission overlay instead.
                if let message = messages.first(where: { $0.id == localMessageID }) {
                    discardLocalMessage(message)
                }
                AppAlertCenter.shared.showPermissionDenied()
            } else {
                updateLocalMessageState(messageID: localMessageID, deliveryState: .failed)
            }
        }
    }

    private func makeLocalBusinessDocumentMessage(
        id: Int,
        currentUser: AuthUser,
        kind: HomeComposerKind,
        establishmentID: Int,
        counterpartyName: String,
        info: String
    ) -> HomeMessage {
        let messageText = [counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines), info.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        return HomeMessage(
            id: id,
            messageType: "document",
            messageText: messageText.isEmpty ? nil : messageText,
            messageOwnerUserID: currentUser.userID,
            messageOwnerUserLogin: currentUser.userLogin,
            messageOwnerFirstName: currentUser.userFirstName,
            messageOwnerSecondName: currentUser.userSecondName,
            messageOwnerProfilePhoto: currentUser.userProfilePhoto,
            messageOrderID: kind == .order ? id : nil,
            messageInventoryID: kind == .inventory ? id : nil,
            messageProductRegistrationID: kind == .productRegistration ? id : nil,
            messageStatus: nil,
            messageStatusColor: nil,
            messageCreatedAt: ISO8601DateFormatter.localMessageTimestamp.string(from: Date()),
            attachments: [],
            order: nil,
            inventory: nil,
            productRegistration: nil,
            deliveryState: .pending
        )
    }
}
