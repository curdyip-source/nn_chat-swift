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
    @Published var messages: [HomeMessage] = []
    @Published var messageDraft = ""
    @Published var isLoading = false
    @Published var isSendingMessage = false
    @Published var loadErrorMessage: String?
    @Published var isAttachmentMenuPresented = false
    @Published var activeComposer: HomeComposerKind?
    @Published var isMediaAlertPresented = false
    @Published var mediaAlertTitle = ""
    @Published var referenceData = HomeReferenceDataResponse(establishments: [], orderMethods: [], statuses: [], currencies: [])
    @Published private(set) var orderCommentReadRevision = 0

    private let client: HomeAPIClient
    private let defaults = UserDefaults.standard
    private var localAttachmentPayloads: [Int: PendingAttachmentUpload] = [:]
    private var pendingBusinessDocumentCreations: [Int: PendingBusinessDocumentCreation] = [:]

    private struct PendingAttachmentUpload {
        let data: Data
        let filename: String
        let mimeType: String
        let attachmentKind: String
        let localFileURL: URL
    }

    private enum PendingBusinessDocumentCreation {
        case order(HomeOrderCreateRequest)
        case inventory(HomeInventoryCreateRequest)
        case productRegistration(HomeProductRegistrationCreateRequest)
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
    }

    private func reloadMessagesInBackground(accessToken: String) {
        Task { [weak self] in
            await self?.reloadMessages(accessToken: accessToken)
        }
    }

    func load(accessToken: String?) async {
        guard let accessToken else {
            messages = []
            loadErrorMessage = "Сессия не найдена"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedMessages = try await client.getMessages(accessToken: accessToken)
            messages = reconcileMessages(with: loadedMessages)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }

        do {
            referenceData = try await client.getReferenceData(accessToken: accessToken)
        } catch {
        }
    }

    func reloadMessages(accessToken: String?) async {
        guard let accessToken else { return }
        do {
            let loadedMessages = try await client.getMessages(accessToken: accessToken)
            messages = reconcileMessages(with: loadedMessages)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    func sendMessage(accessToken: String?) async {
        _ = accessToken
    }

    func sendMessage(accessToken: String?, currentUser: AuthUser, text: String, clearDraft: Bool) async {
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

        do {
            let createdMessage = try await client.sendMessage(accessToken: accessToken, text: normalizedText)
            replaceMessage(localID: localMessageID, with: createdMessage)
            reloadMessagesInBackground(accessToken: accessToken)
        } catch {
            updateLocalMessageState(messageID: localMessageID, deliveryState: .failed)
        }
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
            let createdMessage = try await client.sendMessage(accessToken: accessToken, text: messageText)
            replaceMessage(localID: message.id, with: createdMessage)
            reloadMessagesInBackground(accessToken: accessToken)
        } catch {
            updateLocalMessageState(messageID: message.id, deliveryState: .failed)
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
                ]
            )
            localAttachmentPayloads.removeValue(forKey: localMessageID)
            replaceMessage(localID: localMessageID, with: message)
            scheduleConfirmationReloads(accessToken: accessToken, localMessageID: message.id)
        } catch {
            updateLocalMessageState(messageID: localMessageID, deliveryState: .failed)
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

    func updateOrder(accessToken: String?, orderID: Int, request: HomeOrderUpdateRequest) async throws -> HomeOrder {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let order = try await client.updateOrder(accessToken: accessToken, orderID: orderID, request: request)
        await reloadMessages(accessToken: accessToken)
        return order
    }

    func fetchOrderComments(accessToken: String?, orderID: Int) async throws -> [HomeOrderComment] {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        return try await client.getOrderComments(accessToken: accessToken, orderID: orderID)
    }

    func addOrderComment(accessToken: String?, orderID: Int, text: String) async throws -> HomeOrderComment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let comment = try await client.addOrderComment(accessToken: accessToken, orderID: orderID, text: text)
        reloadMessagesInBackground(accessToken: accessToken)
        return comment
    }

    func addOrderComment(accessToken: String?, orderID: Int, text: String?, attachments: [HomeMessageAttachmentCreateRequest]) async throws -> HomeOrderComment {
        guard let accessToken else {
            throw AuthServiceError.transport("Сессия не найдена")
        }
        let comment = try await client.addOrderComment(accessToken: accessToken, orderID: orderID, text: text, attachments: attachments)
        reloadMessagesInBackground(accessToken: accessToken)
        return comment
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

    func updateOrderStatus(accessToken: String?, order: HomeOrder, statusID: Int) async throws -> HomeOrder {
        try await updateOrder(
            accessToken: accessToken,
            orderID: order.id,
            request: HomeOrderUpdateRequest(
                orderEstablishmentID: order.orderEstablishmentID,
                orderMethodID: order.orderMethodID,
                orderSubMethod: order.orderSubMethod,
                orderCustomer: order.orderCustomer,
                orderInfo: order.orderInfo,
                orderStatusID: statusID,
                items: order.items.map {
                    HomeOrderItemCreateRequest(
                        productID: $0.orderItemProductID,
                        productArticle: $0.orderItemProductID == nil ? $0.orderItemArticle : nil,
                        productName: $0.orderItemProductID == nil ? $0.orderItemName : nil,
                        orderItemQuantity: $0.orderItemQuantity,
                        orderItemPrice: $0.orderItemPrice,
                        orderItemStatusID: $0.orderItemStatusID,
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

    func submitComposer(kind: HomeComposerKind, accessToken: String?, currentUser: AuthUser, establishmentID: Int, orderMethodID: Int?, orderSubMethod: String?, counterpartyName: String, info: String, items: [HomeComposerItemDraft]) async {
        guard let accessToken else { return }
        let normalizedItems = items.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !normalizedItems.isEmpty else { return }

        let localMessageID = nextLocalMessageID()

        switch kind {
        case .order:
            let request = HomeOrderCreateRequest(
                orderEstablishmentID: establishmentID,
                orderMethodID: orderMethodID ?? referenceData.orderMethods.first?.id ?? 1,
                orderSubMethod: orderSubMethod,
                orderCustomer: counterpartyName,
                orderInfo: info,
                items: normalizedItems.map {
                    HomeOrderItemCreateRequest(
                        productID: $0.productID,
                        productArticle: $0.productID == nil ? $0.article : nil,
                        productName: $0.productID == nil ? $0.name : nil,
                        orderItemQuantity: $0.quantity,
                        orderItemPrice: $0.price,
                        orderItemStatusID: nil,
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
            pendingBusinessDocumentCreations[localMessageID] = .order(request)
            mergeMessage(localMessage)
            Task { [weak self] in
                await self?.finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: localMessageID, creation: .order(request))
            }
        case .inventory:
            let request = HomeInventoryCreateRequest(
                inventoryEstablishmentID: establishmentID,
                inventorySupplier: counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : counterpartyName,
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
            pendingBusinessDocumentCreations[localMessageID] = .inventory(request)
            mergeMessage(localMessage)
            Task { [weak self] in
                await self?.finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: localMessageID, creation: .inventory(request))
            }
        case .productRegistration:
            let request = HomeProductRegistrationCreateRequest(
                productRegistrationEstablishmentID: establishmentID,
                productRegistrationSupplier: counterpartyName,
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
            pendingBusinessDocumentCreations[localMessageID] = .productRegistration(request)
            mergeMessage(localMessage)
            Task { [weak self] in
                await self?.finishBusinessDocumentCreation(accessToken: accessToken, localMessageID: localMessageID, creation: .productRegistration(request))
            }
        }
    }

    private func finishBusinessDocumentCreation(accessToken: String, localMessageID: Int, creation: PendingBusinessDocumentCreation) async {
        do {
            switch creation {
            case let .order(request):
                try await client.createOrder(accessToken: accessToken, request: request)
            case let .inventory(request):
                try await client.createInventory(accessToken: accessToken, request: request)
            case let .productRegistration(request):
                try await client.createProductRegistration(accessToken: accessToken, request: request)
            }
            pendingBusinessDocumentCreations.removeValue(forKey: localMessageID)
            updateLocalMessageState(messageID: localMessageID, deliveryState: .sent)
            scheduleConfirmationReloads(accessToken: accessToken, localMessageID: localMessageID)
        } catch {
            updateLocalMessageState(messageID: localMessageID, deliveryState: .failed)
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
