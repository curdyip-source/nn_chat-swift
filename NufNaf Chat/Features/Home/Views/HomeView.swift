//
//  HomeView.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSession
    @StateObject private var store = HomeStore()
    @FocusState private var isMessageFieldFocused: Bool
    @State private var scrollToBottomRequest = 0
    @State private var scrollToMessageRequest = 0
    @State private var scrollToMessageID: Int?
    @State private var replySourceHighlightRequest = 0
    @State private var highlightedMessageID: Int?
    @State private var isChatPinnedToBottom = true
    @State private var replyTarget: HomeMessage?
    @State private var editingMessage: HomeMessage?
    @State private var deletingMessage: HomeMessage?
    @State private var messageActionsTarget: HomeMessage?
    @State private var previewOrder: HomeOrder?
    @State private var previewOrderErrorMessage: String?
    @State private var isUpdatingPreviewOrder = false
    @State private var crmErrorMessage: String?
    @State private var crmUpdatingDocumentKey: String?
    @State private var isPhotoLibraryPresented = false
    @State private var isCameraPresented = false
    @State private var isFilePickerPresented = false
    @State private var pendingAttachmentForConfirmation: PickedChatAttachment?
    @State private var isSendingPendingAttachment = false
    @State private var attachmentErrorMessage: String?
    @State private var messageActionErrorMessage: String?
    @State private var activePhotoAttachment: HomeMessageAttachment?
    @State private var localFilePreview: LocalAttachmentPreview?

    let user: AuthUser

    private var filteredMessages: [HomeMessage] {
        store.messages.filter(matchesActiveFilter)
    }

    private var crmDocumentMessages: [HomeMessage] {
        var seenKeys = Set<String>()

        return filteredMessages.reversed().compactMap { message in
            guard let kind = message.documentKind, let id = message.documentID else {
                return nil
            }

            guard message.order != nil || message.inventory != nil || message.productRegistration != nil else {
                return nil
            }

            let key = documentKey(kind: kind, id: id)
            guard seenKeys.insert(key).inserted else {
                return nil
            }
            return message
        }
    }

    private var chatFilterBinding: Binding<HomeChatFilterState> {
        Binding(
            get: { session.chatFilterState },
            set: { session.updateChatFilterState($0) }
        )
    }

    var body: some View {
        ZStack {
            mainContent
                .blur(radius: messageActionsTarget != nil ? 18 : 0)
                .scaleEffect(messageActionsTarget != nil ? 0.985 : 1)

            attachmentMenuOverlay
            messageActionsBackdropOverlay
            messageActionsOverlay
            deleteConfirmationOverlay
            activeDocumentOverlay

            if let previewOrder {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.previewOrder = nil
                        previewOrderErrorMessage = nil
                    }
                    .zIndex(15)

                ChatOrderPreviewSheet(
                    order: previewOrder,
                    statuses: orderStatuses,
                    itemStatuses: orderItemStatuses,
                    errorMessage: previewOrderErrorMessage,
                    isSaving: isUpdatingPreviewOrder,
                    currencyTitleProvider: currencyTitle(for:),
                    onClose: {
                        self.previewOrder = nil
                        previewOrderErrorMessage = nil
                    },
                    onSelectStatus: { statusID in
                        updatePreviewOrderStatus(statusID: statusID)
                    },
                    onSelectItemStatus: { itemID, statusID in
                        updatePreviewOrderItemStatus(itemID: itemID, statusID: statusID)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(16)
            }

            if let composer = store.activeComposer {
                composerOverlay(for: composer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
            }

            if session.isChecklistOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        session.closeChecklist()
                    }
                    .zIndex(22)

                CRMChecklistSheet(
                    orders: crmDocumentMessages.compactMap(\.order),
                    errorMessage: crmErrorMessage,
                    updatingDocumentKey: crmUpdatingDocumentKey,
                    onClose: {
                        session.closeChecklist()
                    },
                    onToggleStarted: { order, item, isStarted in
                        updateCRMOrderItem(order: order, itemID: item.id, checkpointStarted: isStarted)
                    },
                    onComplete: { order, item in
                        let inStockStatusID = store.referenceData.statuses.first(where: {
                            $0.statusType == "order_products" && $0.statusStatus == "В наличии"
                        })?.id
                        updateCRMOrderItem(
                            order: order,
                            itemID: item.id,
                            statusID: inStockStatusID,
                            checkpointStarted: true,
                            checkpointCompleted: true
                        )
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(23)
            }

            if session.isChatFilterPresented {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        session.closeChatFilterPanel()
                    }
                    .zIndex(24)

                ChatFilterSheet(
                    filter: chatFilterBinding,
                    messages: store.messages,
                    referenceData: store.referenceData,
                    onClose: {
                        session.closeChatFilterPanel()
                    },
                    onReset: {
                        session.updateChatFilterState(session.chatFilterState.resettingCriteria())
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(25)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.activeDocument)
        .animation(.easeInOut(duration: 0.22), value: store.activeComposer)
        .animation(.easeInOut(duration: 0.22), value: previewOrder?.id)
        .animation(.easeInOut(duration: 0.22), value: session.isChatFilterPresented)
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: messageActionsTarget?.id)
        .onChange(of: session.isProfileOpen) { _, isProfileOpen in
            if isProfileOpen {
                dismissKeyboard()
                store.isAttachmentMenuPresented = false
                session.closeChatFilterPanel()
                messageActionsTarget = nil
                deletingMessage = nil
            }
        }
        .onChange(of: session.isChatFilterPresented) { _, isPresented in
            guard isPresented else { return }
            store.isAttachmentMenuPresented = false
            store.activeComposer = nil
            previewOrder = nil
            dismissKeyboard()
        }
        .onChange(of: isMessageFieldFocused) { _, isFocused in
            if isFocused && isChatPinnedToBottom {
                scrollToBottomRequest += 1
            }
        }
        .onChange(of: session.isChecklistOpen) { _, isPresented in
            guard isPresented else { return }
            store.isAttachmentMenuPresented = false
            store.activeComposer = nil
            previewOrder = nil
            dismissKeyboard()
        }
        .onChange(of: session.chatFilterState.displayMode) { _, mode in
            crmErrorMessage = nil

            guard mode == .crm else {
                session.closeChecklist()
                return
            }
            clearInputContext()
            dismissKeyboard()
            store.isAttachmentMenuPresented = false
            previewOrder = nil
        }
        .sheet(isPresented: $isPhotoLibraryPresented) {
            PhotoLibraryAttachmentPicker(
                onPick: { attachment in
                    isPhotoLibraryPresented = false
                    pendingAttachmentForConfirmation = attachment
                },
                onCancel: {
                    isPhotoLibraryPresented = false
                }
            )
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraAttachmentPicker(
                onPick: { attachment in
                    isCameraPresented = false
                    pendingAttachmentForConfirmation = attachment
                },
                onCancel: {
                    isCameraPresented = false
                }
            )
        }
        .sheet(isPresented: $isFilePickerPresented) {
            FileAttachmentPicker(
                onPick: { attachment in
                    isFilePickerPresented = false
                    pendingAttachmentForConfirmation = attachment
                },
                onCancel: {
                    isFilePickerPresented = false
                }
            )
        }
        .sheet(item: $pendingAttachmentForConfirmation) { attachment in
            ChatAttachmentDraftSheet(
                attachment: attachment,
                isSending: isSendingPendingAttachment,
                onCancel: {
                    guard !isSendingPendingAttachment else { return }
                    pendingAttachmentForConfirmation = nil
                },
                onSend: {
                    Task {
                        await sendConfirmedAttachment(attachment)
                    }
                }
            )
        }
        .sheet(item: $localFilePreview) { preview in
            LocalFileQuickLookPreview(fileURL: preview.url)
        }
        .fullScreenCover(item: $activePhotoAttachment) { attachment in
            PhotoAttachmentViewer(attachment: attachment) {
                activePhotoAttachment = nil
            }
        }
        .alert("Не удалось обработать вложение", isPresented: Binding(
            get: { attachmentErrorMessage != nil },
            set: { if !$0 { attachmentErrorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(attachmentErrorMessage ?? "Неизвестная ошибка")
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(
            get: { messageActionErrorMessage != nil },
            set: { if !$0 { messageActionErrorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(messageActionErrorMessage ?? "Неизвестная ошибка")
        }
        .task(id: "\(user.userID)-\(session.currentAccessToken ?? "no-token")") {
            await store.load(accessToken: session.currentAccessToken)
        }
        .task(id: "chat-refresh-\(user.userID)-\(session.currentAccessToken ?? "no-token")-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                await store.reloadMessages(accessToken: session.currentAccessToken)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await store.reloadMessages(accessToken: session.currentAccessToken)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch session.chatFilterState.displayMode {
        case .chat:
            chatContent
        case .crm:
            crmContent
        }
    }

    private var chatContent: some View {
        VStack(spacing: 14) {
            if let loadErrorMessage = store.loadErrorMessage {
                Text("Ошибка загрузки чата: \(loadErrorMessage)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.isLoading && store.messages.isEmpty {
                Text("Загружаем историю сообщений...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.mutedText)
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ChatMessagesView(
                messages: filteredMessages,
                currentUserID: user.userID,
                scrollToBottomRequest: scrollToBottomRequest,
                scrollToMessageRequest: scrollToMessageRequest,
                scrollToMessageID: scrollToMessageID,
                highlightedMessageID: highlightedMessageID,
                highlightMessageRequest: replySourceHighlightRequest,
                unreadOrderCommentsCount: { order in
                    store.unreadOrderCommentCount(for: order, currentUserID: user.userID)
                },
                onOpenDocument: { kind, id in
                    session.closeChatFilterPanel()
                    previewOrder = nil
                    session.openDocument(kind: kind, id: id)
                },
                onPreviewOrder: { order in
                    session.closeChatFilterPanel()
                    closeAttachmentMenu()
                    previewOrderErrorMessage = nil
                    previewOrder = order
                },
                onOpenReplySource: { message in
                    openReplySource(for: message)
                },
                onShowMessageActions: { message in
                    dismissKeyboard()
                    closeAttachmentMenu()
                    previewOrder = nil
                    messageActionsTarget = message
                },
                onReplyMessage: { message in
                    editingMessage = nil
                    replyTarget = message
                    isMessageFieldFocused = true
                    scrollToBottomRequest += 1
                },
                onEditMessage: { message in
                    replyTarget = nil
                    editingMessage = message
                    store.messageDraft = message.messageText ?? ""
                    isMessageFieldFocused = true
                    scrollToBottomRequest += 1
                },
                onDeleteMessage: { message in
                    deletingMessage = message
                },
                onRetryMessage: { message in
                    Task {
                        await retryFailedMessage(message)
                    }
                },
                onOpenAttachment: { attachment in
                    openAttachment(attachment)
                },
                onBackgroundTap: {
                    dismissKeyboard()
                },
                onPinnedToBottomChange: { value in
                    isChatPinnedToBottom = value
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputPanel(
                text: $store.messageDraft,
                isTextFieldFocused: $isMessageFieldFocused,
                inputContext: inputContext,
                isSending: store.isSendingMessage,
                onAttach: {
                    dismissKeyboard()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        store.isAttachmentMenuPresented.toggle()
                    }
                },
                onCancelInputContext: {
                    clearInputContext()
                },
                onSend: {
                    Task {
                        await submitChatInput()
                    }
                }
            )
            .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, max(AppTheme.PageLayout.bottomPadding - 8, 8))
            .background(AppTheme.background.opacity(0.96))
        }
    }

    private var crmContent: some View {
        CRMDocumentsListView(
            messages: crmDocumentMessages,
            referenceData: store.referenceData,
            isLoading: store.isLoading,
            errorMessage: crmErrorMessage ?? store.loadErrorMessage,
            updatingDocumentKey: crmUpdatingDocumentKey,
            onOpenDocument: { kind, id in
                session.closeChatFilterPanel()
                previewOrder = nil
                session.openDocument(kind: kind, id: id)
            },
            onSelectOrderStatus: { order, statusID in
                updateCRMOrderStatus(order: order, statusID: statusID)
            },
            onSelectOrderItemStatus: { order, itemID, statusID, sourceID, destinationID in
                updateCRMOrderItem(
                    order: order,
                    itemID: itemID,
                    statusID: statusID,
                    sourceEstablishmentID: sourceID,
                    destinationEstablishmentID: destinationID
                )
            },
            onSelectInventoryStatus: { inventory, statusID in
                updateCRMInventoryStatus(inventory: inventory, statusID: statusID)
            },
            onSelectProductRegistrationStatus: { registration, statusID in
                updateCRMProductRegistrationStatus(registration: registration, statusID: statusID)
            }
        )
    }

    private var inputContext: ChatInputContext? {
        if let editingMessage {
            return ChatInputContext(
                kind: .edit,
                title: "Ваше сообщение",
                subtitle: (editingMessage.messageText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if let replyTarget {
            return ChatInputContext(
                kind: .reply,
                title: replyTarget.displayName,
                subtitle: replySnippet(for: replyTarget)
            )
        }

        return nil
    }

    private var orderStatuses: [HomeStatus] {
        store.referenceData.statuses.filter { $0.statusType == "orders" }
    }

    private var orderItemStatuses: [HomeStatus] {
        store.referenceData.statuses.filter { $0.statusType == "order_products" }
    }

    @ViewBuilder
    private var attachmentMenuOverlay: some View {
        if store.isAttachmentMenuPresented {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeAttachmentMenu()
                }
                .zIndex(5)

            AttachmentActionMenu(
                onPhotoTap: { presentAttachmentAction(kind: "Фото") },
                onCameraTap: { presentAttachmentAction(kind: "Камера") },
                onFileTap: { presentAttachmentAction(kind: "Файл") },
                onOrderTap: { presentComposer(.order) },
                onProductRegistrationTap: { presentComposer(.productRegistration) },
                onInventoryTap: { presentComposer(.inventory) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, AppTheme.PageLayout.horizontalPadding + 2)
            .padding(.bottom, AppTheme.PageLayout.bottomPadding + 58)
            .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity), removal: .opacity))
            .zIndex(6)
        }
    }

    @ViewBuilder
    private var messageActionsBackdropOverlay: some View {
        if messageActionsTarget != nil {
            GeometryReader { proxy in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.24))
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height + fullscreenBackdropOverscan
                    )
                    .offset(y: -fullscreenBackdropOverscan)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        messageActionsTarget = nil
                    }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .zIndex(11)
        } else if deletingMessage != nil {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    deletingMessage = nil
                }
                .zIndex(11)
        }
    }

    private var fullscreenBackdropOverscan: CGFloat {
        UIScreen.main.bounds.height
    }

    @ViewBuilder
    private var messageActionsOverlay: some View {
        if let messageActionsTarget {
            ChatMessageFocusOverlay(
                message: messageActionsTarget,
                isOwnMessage: messageActionsTarget.messageOwnerUserID == user.userID,
                onReply: {
                    editingMessage = nil
                    replyTarget = messageActionsTarget
                    isMessageFieldFocused = true
                    self.messageActionsTarget = nil
                },
                onEdit: {
                    replyTarget = nil
                    editingMessage = messageActionsTarget
                    store.messageDraft = messageActionsTarget.messageText ?? ""
                    isMessageFieldFocused = true
                    self.messageActionsTarget = nil
                },
                onDelete: {
                    deletingMessage = messageActionsTarget
                    self.messageActionsTarget = nil
                }
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 108)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            .zIndex(12)
        }
    }

    @ViewBuilder
    private var deleteConfirmationOverlay: some View {
        if let deletingMessage {
            ChatMessageDeleteSheet(
                onConfirm: {
                    let target = deletingMessage
                    self.deletingMessage = nil
                    Task {
                        await deleteMessage(target)
                    }
                },
                onCancel: {
                    self.deletingMessage = nil
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(13)
        }
    }

    @ViewBuilder
    private var activeDocumentOverlay: some View {
        if let document = session.activeDocument {
            if document.kind == "order" {
                OrderDetailView(store: store, orderID: document.id) {
                    session.closeDocument()
                }
                .environmentObject(session)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(10)
            } else if document.kind == "inventory" {
                InventoryDetailView(store: store, inventoryID: document.id) {
                    session.closeDocument()
                }
                .environmentObject(session)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(10)
            } else if document.kind == "product_registration" {
                ProductRegistrationDetailView(store: store, productRegistrationID: document.id) {
                    session.closeDocument()
                }
                .environmentObject(session)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(10)
            }
        }
    }

    private func closeAttachmentMenu() {
        dismissKeyboard()
        withAnimation(.easeOut(duration: 0.16)) {
            store.isAttachmentMenuPresented = false
        }
    }

    private func dismissKeyboard() {
        isMessageFieldFocused = false
    }

    private func presentAttachmentAction(kind: String) {
        session.closeChatFilterPanel()
        closeAttachmentMenu()

        switch kind {
        case "Фото":
            isPhotoLibraryPresented = true
        case "Камера":
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                attachmentErrorMessage = "Камера на этом устройстве недоступна"
                return
            }
            isCameraPresented = true
        case "Файл":
            isFilePickerPresented = true
        default:
            store.presentMediaPlaceholder(kind: kind)
        }
    }

    private func sendConfirmedAttachment(_ attachment: PickedChatAttachment) async {
        guard !isSendingPendingAttachment else { return }

        isSendingPendingAttachment = true
        defer { isSendingPendingAttachment = false }

        do {
            _ = try await store.sendAttachment(
                accessToken: session.currentAccessToken,
                currentUser: user,
                data: attachment.data,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                attachmentKind: attachment.attachmentKind
            )
            pendingAttachmentForConfirmation = nil
            scrollToBottomRequest += 1
        } catch {
            attachmentErrorMessage = error.localizedDescription
        }
    }

    private func openAttachment(_ attachment: HomeMessageAttachment) {
        if attachment.isPhoto {
            activePhotoAttachment = attachment
            return
        }

        if let localURL = attachment.localFileURL {
            localFilePreview = LocalAttachmentPreview(url: localURL)
            return
        }

        Task {
            do {
                let localURL = try await store.downloadAttachmentToTemporaryURL(attachment)
                localFilePreview = LocalAttachmentPreview(url: localURL)
            } catch {
                attachmentErrorMessage = error.localizedDescription
            }
        }
    }

    private func openReplySource(for message: HomeMessage) {
        guard let reply = message.replyFragment else { return }

        let visibleCandidates = filteredMessages.filter { candidate in
            candidate.id != message.id
                && candidate.displayName == reply.author
                && candidate.replyReferenceText == reply.message
        }

        let matchingCandidates = visibleCandidates.isEmpty ? store.messages.filter { candidate in
            candidate.id != message.id
                && candidate.displayName == reply.author
                && candidate.replyReferenceText == reply.message
        } : visibleCandidates

        let targetMessage = matchingCandidates
            .filter { candidate in
                guard let messageDate = message.parsedCreatedAt,
                      let candidateDate = candidate.parsedCreatedAt else {
                    return true
                }
                return candidateDate <= messageDate
            }
            .sorted { lhs, rhs in
                switch (lhs.parsedCreatedAt, rhs.parsedCreatedAt) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate > rightDate
                default:
                    return lhs.id > rhs.id
                }
            }
            .first

        guard let targetMessage else { return }
        scrollToMessageID = targetMessage.id
        highlightedMessageID = targetMessage.id
        replySourceHighlightRequest += 1
        scrollToMessageRequest += 1

        let currentHighlightRequest = replySourceHighlightRequest
        let currentMessageID = targetMessage.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard replySourceHighlightRequest == currentHighlightRequest else { return }
            guard highlightedMessageID == currentMessageID else { return }
            highlightedMessageID = nil
        }
    }

    private func presentComposer(_ kind: HomeComposerKind) {
        session.closeChatFilterPanel()
        closeAttachmentMenu()
        store.activeComposer = kind
    }

    private func clearInputContext() {
        replyTarget = nil
        editingMessage = nil
    }

    private func replySnippet(for message: HomeMessage) -> String {
        message.replyReferenceText
    }

    private func composedReplyText(from text: String) -> String {
        guard let replyTarget else { return text }
        return "| \(replyTarget.displayName)\n> \(replySnippet(for: replyTarget))\n\(text)"
    }

    private func submitChatInput() async {
        let trimmedText = store.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if let editingMessage {
            do {
                _ = try await store.updateMessage(accessToken: session.currentAccessToken, messageID: editingMessage.id, text: trimmedText)
                store.messageDraft = ""
                self.editingMessage = nil
                isMessageFieldFocused = true
            } catch {
            }
            return
        }

        guard let accessToken = session.currentAccessToken else { return }
        let composedText = composedReplyText(from: trimmedText)
        replyTarget = nil
        await store.sendMessage(accessToken: accessToken, currentUser: user, text: composedText, clearDraft: true)
        isMessageFieldFocused = true
        scrollToBottomRequest += 1
    }

    private func retryFailedMessage(_ message: HomeMessage) async {
        await store.retryFailedMessage(accessToken: session.currentAccessToken, currentUser: user, message: message)
        scrollToBottomRequest += 1
    }

    private func deleteMessage(_ message: HomeMessage) async {
        if editingMessage?.id == message.id {
            editingMessage = nil
            store.messageDraft = ""
        }
        if replyTarget?.id == message.id {
            replyTarget = nil
        }

        deletingMessage = nil

        do {
            try await store.deleteMessage(accessToken: session.currentAccessToken, message: message)
        } catch {
            messageActionErrorMessage = error.localizedDescription
        }
    }

    private func updatePreviewOrderStatus(statusID: Int) {
        guard let previewOrder else { return }
        guard previewOrder.orderStatusID != statusID else { return }

        Task {
            isUpdatingPreviewOrder = true
            previewOrderErrorMessage = nil
            defer { isUpdatingPreviewOrder = false }

            do {
                self.previewOrder = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: previewOrder, statusID: statusID)
            } catch {
                previewOrderErrorMessage = error.localizedDescription
            }
        }
    }

    private func updatePreviewOrderItemStatus(itemID: Int, statusID: Int) {
        guard let previewOrder else { return }
        guard let currentItem = previewOrder.items.first(where: { $0.id == itemID }) else { return }
        guard currentItem.orderItemStatusID != statusID else { return }

        let resetCheckpoints = shouldResetChecklistState(for: statusID)

        Task {
            isUpdatingPreviewOrder = true
            previewOrderErrorMessage = nil
            defer { isUpdatingPreviewOrder = false }

            do {
                self.previewOrder = try await store.updateOrder(
                    accessToken: session.currentAccessToken,
                    orderID: previewOrder.id,
                    request: HomeOrderUpdateRequest(
                        orderEstablishmentID: previewOrder.orderEstablishmentID,
                        orderMethodID: previewOrder.orderMethodID,
                        orderSubMethod: previewOrder.orderSubMethod,
                        orderCustomer: previewOrder.orderCustomer,
                        orderInfo: previewOrder.orderInfo,
                        orderStatusID: previewOrder.orderStatusID,
                        items: previewOrder.items.map { item in
                            makeOrderItemRequest(
                                item: item,
                                statusID: item.id == itemID ? statusID : item.orderItemStatusID,
                                checkpointStarted: item.id == itemID && resetCheckpoints ? false : item.orderItemCheckpointStarted,
                                checkpointCompleted: item.id == itemID && resetCheckpoints ? false : item.orderItemCheckpointCompleted
                            )
                        }
                    )
                )
            } catch {
                previewOrderErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateCRMOrderStatus(order: HomeOrder, statusID: Int) {
        guard order.orderStatusID != statusID else { return }

        Task {
            crmUpdatingDocumentKey = documentKey(kind: "order", id: order.id)
            crmErrorMessage = nil
            defer { crmUpdatingDocumentKey = nil }

            do {
                _ = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: order, statusID: statusID)
            } catch {
                crmErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateCRMOrderItemStatus(order: HomeOrder, itemID: Int, statusID: Int) {
        updateCRMOrderItem(order: order, itemID: itemID, statusID: statusID)
    }

    private func updateCRMOrderItem(
        order: HomeOrder,
        itemID: Int,
        statusID: Int? = nil,
        sourceEstablishmentID: Int? = nil,
        destinationEstablishmentID: Int? = nil,
        checkpointStarted: Bool? = nil,
        checkpointCompleted: Bool? = nil
    ) {
        guard let currentItem = order.items.first(where: { $0.id == itemID }) else { return }

        let nextStatusID = statusID ?? currentItem.orderItemStatusID
        let nextSourceID = sourceEstablishmentID ?? currentItem.orderItemSourceEstablishmentID
        let nextDestinationID = destinationEstablishmentID ?? currentItem.orderItemDestinationEstablishmentID
        let resetCheckpoints = statusID != nil && statusID != currentItem.orderItemStatusID && shouldResetChecklistState(for: nextStatusID)
        let nextStarted = checkpointStarted ?? (resetCheckpoints ? false : currentItem.orderItemCheckpointStarted)
        let nextCompleted = checkpointCompleted ?? (resetCheckpoints ? false : currentItem.orderItemCheckpointCompleted)

        guard currentItem.orderItemStatusID != nextStatusID
            || currentItem.orderItemSourceEstablishmentID != nextSourceID
            || currentItem.orderItemDestinationEstablishmentID != nextDestinationID
            || currentItem.orderItemCheckpointStarted != nextStarted
            || currentItem.orderItemCheckpointCompleted != nextCompleted else {
            return
        }

        Task {
            crmUpdatingDocumentKey = documentKey(kind: "order", id: order.id)
            crmErrorMessage = nil
            defer { crmUpdatingDocumentKey = nil }

            do {
                _ = try await store.updateOrder(
                    accessToken: session.currentAccessToken,
                    orderID: order.id,
                    request: HomeOrderUpdateRequest(
                        orderEstablishmentID: order.orderEstablishmentID,
                        orderMethodID: order.orderMethodID,
                        orderSubMethod: order.orderSubMethod,
                        orderCustomer: order.orderCustomer,
                        orderInfo: order.orderInfo,
                        orderStatusID: order.orderStatusID,
                        items: order.items.map { item in
                            makeOrderItemRequest(
                                item: item,
                                statusID: item.id == itemID ? nextStatusID : item.orderItemStatusID,
                                sourceEstablishmentID: item.id == itemID ? nextSourceID : item.orderItemSourceEstablishmentID,
                                destinationEstablishmentID: item.id == itemID ? nextDestinationID : item.orderItemDestinationEstablishmentID,
                                checkpointStarted: item.id == itemID ? nextStarted : item.orderItemCheckpointStarted,
                                checkpointCompleted: item.id == itemID ? nextCompleted : item.orderItemCheckpointCompleted
                            )
                        }
                    )
                )
            } catch {
                crmErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateCRMInventoryStatus(inventory: HomeInventory, statusID: Int) {
        guard inventory.inventoryStatusID != statusID else { return }

        Task {
            crmUpdatingDocumentKey = documentKey(kind: "inventory", id: inventory.id)
            crmErrorMessage = nil
            defer { crmUpdatingDocumentKey = nil }

            do {
                _ = try await store.updateInventoryStatus(accessToken: session.currentAccessToken, inventoryID: inventory.id, statusID: statusID)
            } catch {
                crmErrorMessage = error.localizedDescription
            }
        }
    }

    private func updateCRMProductRegistrationStatus(registration: HomeProductRegistration, statusID: Int) {
        guard registration.productRegistrationStatusID != statusID else { return }

        Task {
            crmUpdatingDocumentKey = documentKey(kind: "product_registration", id: registration.id)
            crmErrorMessage = nil
            defer { crmUpdatingDocumentKey = nil }

            do {
                _ = try await store.updateProductRegistrationStatus(accessToken: session.currentAccessToken, productRegistrationID: registration.id, statusID: statusID)
            } catch {
                crmErrorMessage = error.localizedDescription
            }
        }
    }

    private func documentKey(kind: String, id: Int) -> String {
        "\(kind):\(id)"
    }

    private func makeOrderItemRequest(
        item: HomeOrderItem,
        statusID: Int? = nil,
        sourceEstablishmentID: Int? = nil,
        destinationEstablishmentID: Int? = nil,
        checkpointStarted: Bool? = nil,
        checkpointCompleted: Bool? = nil
    ) -> HomeOrderItemCreateRequest {
        HomeOrderItemCreateRequest(
            productID: item.orderItemProductID,
            productArticle: item.orderItemProductID == nil ? item.orderItemArticle : nil,
            productName: item.orderItemProductID == nil ? item.orderItemName : nil,
            orderItemQuantity: item.orderItemQuantity,
            orderItemPrice: item.orderItemPrice,
            orderItemStatusID: statusID ?? item.orderItemStatusID,
            orderItemSourceEstablishmentID: sourceEstablishmentID ?? item.orderItemSourceEstablishmentID,
            orderItemDestinationEstablishmentID: destinationEstablishmentID ?? item.orderItemDestinationEstablishmentID,
            orderItemCurrencyID: item.orderItemCurrencyID,
            orderItemCheckpointStarted: checkpointStarted ?? item.orderItemCheckpointStarted,
            orderItemCheckpointCompleted: checkpointCompleted ?? item.orderItemCheckpointCompleted
        )
    }

    private func shouldResetChecklistState(for statusID: Int?) -> Bool {
        guard let statusID else { return false }
        guard let status = store.referenceData.statuses.first(where: { $0.id == statusID }) else { return false }
        return status.statusType == "order_products" && ["Заказ", "Перемещение"].contains(status.statusStatus)
    }

    private func currencyTitle(for currencyID: Int?) -> String {
        guard let currency = store.referenceData.currencies.first(where: { $0.id == currencyID }) else {
            return "USD"
        }
        if let sign = currency.currencySign, !sign.isEmpty {
            return sign
        }
        return currency.currencyName
    }

    private func matchesActiveFilter(_ message: HomeMessage) -> Bool {
        let filter = session.chatFilterState
        let kind = message.filterKind

        if let createdAt = message.parsedCreatedAt {
            let calendar = Calendar.current
            if calendar.component(.year, from: createdAt) != filter.year {
                return false
            }
            if !filter.months.isEmpty, !filter.months.contains(calendar.component(.month, from: createdAt)) {
                return false
            }
        }

        if !filter.kinds.isEmpty, !filter.kinds.contains(kind) {
            return false
        }

        if kind != .message, !filter.establishmentIDs.isEmpty {
            guard let establishmentID = message.filterEstablishmentID,
                  filter.establishmentIDs.contains(establishmentID) else {
                return false
            }
        }

        if kind != .message, !filter.statusIDs.isEmpty {
            guard let statusID = message.filterStatusID,
                  filter.statusIDs.contains(statusID) else {
                return false
            }
        }

        if kind != .message
            && filter.hideCompleted
            && isCompletedMessage(message)
            && !isExplicitlySelectedCompletedStatus(message.filterStatusID, in: filter.statusIDs) {
            return false
        }

        return true
    }

    private func isExplicitlySelectedCompletedStatus(_ statusID: Int?, in selectedStatusIDs: Set<Int>) -> Bool {
        guard let statusID, selectedStatusIDs.contains(statusID) else { return false }
        guard let status = store.referenceData.statuses.first(where: { $0.id == statusID }) else { return false }
        return isCompletedStatusTitle(status.statusStatus)
    }

    private func isCompletedMessage(_ message: HomeMessage) -> Bool {
        guard message.filterKind != .message else { return false }
        return isCompletedStatusTitle(message.filterStatusText)
    }

    private func isCompletedStatusTitle(_ statusTitle: String?) -> Bool {
        let normalizedStatus = (statusTitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedStatus.isEmpty else { return false }
        return normalizedStatus.contains("выполн")
            || normalizedStatus.contains("заверш")
            || normalizedStatus.contains("принято")
            || normalizedStatus.contains("done")
            || normalizedStatus.contains("complete")
    }

    @ViewBuilder
    private func composerOverlay(for composer: HomeComposerKind) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            ComposerSheetView(kind: composer, store: store) {
                store.activeComposer = nil
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.9)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 42, height: 5)
                    .padding(.top, 10)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: -4)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

private struct AttachmentActionMenu: View {
    let onPhotoTap: () -> Void
    let onCameraTap: () -> Void
    let onFileTap: () -> Void
    let onOrderTap: () -> Void
    let onProductRegistrationTap: () -> Void
    let onInventoryTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Файл или фото")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            menuDivider

            AttachmentMenuButton(title: "Фото", action: onPhotoTap)
            AttachmentMenuButton(title: "Камера", action: onCameraTap)
            AttachmentMenuButton(title: "Файл", action: onFileTap)

            Text("Документы")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            menuDivider

            AttachmentMenuButton(title: "Заказ", action: onOrderTap)
            AttachmentMenuButton(title: "Приемка", action: onProductRegistrationTap)
            AttachmentMenuButton(title: "Инвентаризация", action: onInventoryTap)
        }
        .frame(width: 228, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
        )
        .overlay(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(45))
                .offset(x: 18, y: 6)
        }
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct AttachmentMenuButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatMessageActionMenu: View {
    let message: HomeMessage
    let isOwnMessage: Bool
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var canReply: Bool {
        !message.isLocalOnly
    }

    private var canEdit: Bool {
        message.documentKind == nil && message.attachments.isEmpty && message.messageType == "message" && message.deliveryState == .sent
    }

    private var canDelete: Bool {
        message.documentKind == nil && isOwnMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if canReply {
                MessageActionButton(title: "Ответить", action: onReply)
            }

            if canEdit {
                if canReply {
                    menuDivider
                }
                MessageActionButton(title: "Изменить", action: onEdit)
            }

            if canDelete {
                if canReply || canEdit {
                    menuDivider
                }
                MessageActionButton(title: "Удалить", isDestructive: true, action: onDelete)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct ChatMessageFocusOverlay: View {
    let message: HomeMessage
    let isOwnMessage: Bool
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if isOwnMessage {
                Spacer(minLength: 54)
            }

            VStack(alignment: .trailing, spacing: 10) {
                ChatFocusedMessagePreview(message: message, isOwnMessage: isOwnMessage)

                ChatMessageActionMenu(
                    message: message,
                    isOwnMessage: isOwnMessage,
                    onReply: onReply,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
            .frame(maxWidth: 310, alignment: .trailing)

            if !isOwnMessage {
                Spacer(minLength: 54)
            }
        }
    }
}

private struct ChatFocusedMessagePreview: View {
    let message: HomeMessage
    let isOwnMessage: Bool

    var body: some View {
        Group {
            if message.documentKind != nil {
                documentPreview
            } else if !message.attachments.isEmpty {
                attachmentPreview
            } else {
                textPreview
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reply = message.replyFragment {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reply.author)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(replyForegroundColor)
                        .lineLimit(1)

                    if !reply.message.isEmpty {
                        Text(reply.message)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(replyForegroundColor.opacity(0.82))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(replyBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !message.visibleMessageText.isEmpty {
                Text(message.visibleMessageText)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metaLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(textBubbleBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(textBubbleBorderColor, lineWidth: 1)
                )
        )
    }

    private var attachmentPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(message.attachments) { attachment in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(attachmentPreviewBackgroundColor)
                        .frame(width: 52, height: 52)
                        .overlay {
                            if attachment.isPhoto, let mediaURL = attachment.mediaURL {
                                AsyncImage(url: mediaURL) { phase in
                                    switch phase {
                                    case let .success(image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(iconForegroundColor)
                                    default:
                                        ProgressView()
                                            .tint(iconForegroundColor)
                                    }
                                }
                            } else {
                                Image(systemName: attachment.isPhoto ? "photo" : "doc")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(iconForegroundColor)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(attachment.attachmentOriginalFilename)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryAttachmentTextColor)
                            .lineLimit(2)

                        if let attachmentSizeBytes = attachment.attachmentSizeBytes {
                            Text(sizeTitle(bytes: attachmentSizeBytes))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(secondaryAttachmentTextColor)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            metaLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(attachmentBubbleBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(attachmentBubbleBorderColor, lineWidth: 1)
                )
        )
    }

    private var documentPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(documentTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let documentID = message.documentID {
                        Text("document_id: \(documentID)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                Spacer(minLength: 0)

                if let status = message.messageStatus {
                    Text(status)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusBackgroundColor, in: Capsule())
                }
            }

            if let messageText = message.messageText, !messageText.isEmpty {
                Text(messageText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            metaLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.18, green: 0.18, blue: 0.21))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var metaLine: some View {
        HStack {
            Spacer(minLength: 0)

            Text(formattedTimestamp)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryForegroundColor)
        }
    }

    private var replyForegroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.72) : Color.white.opacity(0.82)
    }

    private var replyBackgroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }

    private var secondaryForegroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.68) : Color.white.opacity(0.68)
    }

    private var iconForegroundColor: Color {
        (isOwnMessage ? Color.black : Color.white).opacity(0.8)
    }

    private var primaryTextColor: Color {
        isOwnMessage ? Color.black : Color.white
    }

    private var textBubbleBackgroundColor: Color {
        isOwnMessage ? Color.white : Color(red: 0.16, green: 0.16, blue: 0.19)
    }

    private var textBubbleBorderColor: Color {
        isOwnMessage ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
    }

    private var attachmentBubbleBackgroundColor: Color {
        isOwnMessage ? Color.white : Color(red: 0.18, green: 0.18, blue: 0.21)
    }

    private var attachmentBubbleBorderColor: Color {
        isOwnMessage ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
    }

    private var primaryAttachmentTextColor: Color {
        isOwnMessage ? Color.black : Color.white
    }

    private var secondaryAttachmentTextColor: Color {
        (isOwnMessage ? Color.black : Color.white).opacity(0.68)
    }

    private var attachmentPreviewBackgroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.06) : Color.white.opacity(0.10)
    }

    private var documentTitle: String {
        switch message.documentKind {
        case "order":
            return "Заказ"
        case "inventory":
            return "Инвентаризация"
        case "product_registration":
            return "Приемка"
        default:
            return "Документ"
        }
    }

    private var statusBackgroundColor: Color {
        switch (message.messageStatusColor ?? "").lowercased() {
        case "green":
            return Color(red: 0.16, green: 0.52, blue: 0.31)
        case "orange":
            return Color(red: 0.78, green: 0.44, blue: 0.12)
        case "blue":
            return Color(red: 0.20, green: 0.40, blue: 0.78)
        default:
            return Color.white.opacity(0.16)
        }
    }

    private var formattedTimestamp: String {
        if let date = message.parsedCreatedAt {
            return Self.displayFormatter.string(from: date)
        }
        return message.messageCreatedAt ?? ""
    }

    private func sizeTitle(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct ChatMessageDeleteSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Удалить сообщение?")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Сообщение будет удалено для всех участников чата.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Удалить для всех")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct MessageActionButton: View {
    let title: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isDestructive ? Color.red.opacity(0.92) : .white)
                .frame(alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    PageTemplate {
        HomeView(
            user: AuthUser(
                userID: 1,
                userLogin: "demo",
                userAdmin: false,
                userActive: true,
                userFirstName: "Иван",
                userSecondName: "Иванов",
                userProfilePhoto: nil,
                userAge: 0,
                userAddress: "-",
                userVerifiedUserID: nil,
                userCreatedAt: nil
            )
        )
    }
    .environmentObject(AppSession())
}
