//
//  HomeView.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

struct PendingAssemblySplit: Identifiable {
    let id = UUID()
    let order: HomeOrder
    let isPreview: Bool
}

/// Диалог предложения сплита при переводе смешанного заказа в «На сборку».
/// Вынесен в модификатор, чтобы не раздувать type-check тела HomeView.
private struct AssemblySplitDialogModifier: ViewModifier {
    @Binding var pending: PendingAssemblySplit?
    @Binding var alertMessage: String?
    let onConfirm: (PendingAssemblySplit) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let value = pending {
                    AppConfirmCard(
                        title: "Разделить заказ?",
                        message: "В заказе есть товары не в наличии. «В наличии» уйдут на сборку, остальные — в новый заказ (дубль).",
                        buttons: [
                            AppConfirmButton(label: "Разделить и на сборку", style: .primary) {
                                pending = nil
                                onConfirm(value)
                            },
                            AppConfirmButton(label: "Отмена", style: .cancel) { pending = nil },
                        ]
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: pending?.id)
            .alert(
                "Нельзя перевести в «На сборку»",
                isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
            ) {
                Button("Понятно", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
    }
}

struct PendingOrderCancel: Identifiable {
    let id = UUID()
    let order: HomeOrder
    let statusID: Int
    let isPreview: Bool
}

/// Диалог при переводе заказа в «Отменен»: отменить и все товары или оставить их статусы.
private struct OrderCancelDialogModifier: ViewModifier {
    @Binding var pending: PendingOrderCancel?
    let onChoose: (PendingOrderCancel, Bool) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let value = pending {
                    AppConfirmCard(
                        title: "Отменить заказ",
                        message: "Отменить и все товары заказа, или оставить их текущие статусы?",
                        buttons: [
                            AppConfirmButton(label: "Отменить и все товары", style: .destructive) {
                                pending = nil
                                onChoose(value, true)
                            },
                            AppConfirmButton(label: "Оставить статусы товаров", style: .primary) {
                                pending = nil
                                onChoose(value, false)
                            },
                            AppConfirmButton(label: "Отмена", style: .cancel) { pending = nil },
                        ]
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: pending?.id)
    }
}

/// Пересчёт производных списков ленты по дешёвым ключам (счётчик изменений ленты,
/// фильтр, строка поиска) — отдельным модификатором, чтобы не удлинять и без того
/// длинную цепочку модификаторов тела HomeView.
private struct DerivedMessagesTrigger: ViewModifier {
    let revision: Int
    let filter: HomeChatFilterState
    let search: String
    let rebuild: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: rebuild)
            .onChange(of: revision) { _, _ in rebuild() }
            .onChange(of: filter) { _, _ in rebuild() }
            .onChange(of: search) { _, _ in rebuild() }
    }
}

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @StateObject private var store = HomeStore()
    @State private var isMessageFieldFocused = false
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
    /// Лента разделов «Задач» сейчас едет — на это время листание экранов выключаем,
    /// иначе на краю ленты остаток жеста уходит пейджеру и экран дёргается.
    @State private var isTodoSectionBarScrolling = false
    @State private var previewOrder: HomeOrder?
    @State private var previewOrderErrorMessage: String?
    @State private var isUpdatingPreviewOrder = false
    @State private var crmErrorMessage: String?
    @State private var crmUpdatingDocumentKey: String?
    @State private var pendingAssemblySplit: PendingAssemblySplit?
    @State private var pendingOrderCancel: PendingOrderCancel?
    @State private var assemblyAlertMessage: String?
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

    // Идентификаторы .task вынесены из тела: длинные интерполяции прямо в модификаторах
    // раздували выражение тела так, что компилятор переставал его тайпчекать.
    private var sessionTaskID: String {
        "\(user.userID)-\(session.currentAccessToken ?? "no-token")"
    }

    private var chatStreamTaskID: String {
        "chat-stream-\(sessionTaskID)-\(scenePhase == .active)"
    }

    private var chatRefreshTaskID: String {
        "chat-refresh-\(sessionTaskID)-\(scenePhase == .active)"
    }

    /// Кэш производных списков (см. rebuildDerivedMessages).
    @State private var derivedFilteredMessages: [HomeMessage] = []
    @State private var derivedCRMDocumentMessages: [HomeMessage] = []

    // Отфильтрованная лента и карточки СРМ считаются ОДИН раз на изменение данных
    // (лента, фильтр, поиск), а не в теле вью. Тело перевычисляется в том числе на
    // каждом кадре свайпа между режимами, а обе выборки — полный проход по всей
    // истории (сотни сообщений, у карточек ещё дедуп и поиск по позициям). Именно
    // это подлагивало при снятой галочке «скрыть выполненные», когда в выборку
    // попадает вся история, а не десяток активных заказов.
    private var filteredMessages: [HomeMessage] { derivedFilteredMessages }

    private var crmDocumentMessages: [HomeMessage] { derivedCRMDocumentMessages }

    /// Пересчёт производных списков. Вызывается по изменению ленты/фильтра/поиска.
    private func rebuildDerivedMessages() {
        let filtered = store.messages.filter(matchesActiveFilter)
        derivedFilteredMessages = filtered
        derivedCRMDocumentMessages = crmDocuments(from: filtered)
    }

    private func crmDocuments(from messages: [HomeMessage]) -> [HomeMessage] {
        var seenKeys = Set<String>()

        return messages.reversed().compactMap { message in
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
            guard matchesCRMSearch(message) else {
                return nil
            }
            return message
        }
    }

    private var normalizedCRMSearchQuery: String {
        session.crmSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chatFilterBinding: Binding<HomeChatFilterState> {
        Binding(
            get: { session.chatFilterState },
            set: { session.updateChatFilterState($0) }
        )
    }

    private var currentDisplayMode: HomeDisplayMode {
        session.chatFilterState.displayMode
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                swipeableMainContent(containerWidth: proxy.size.width)
                    .modifier(DerivedMessagesTrigger(
                        revision: store.messagesRevision,
                        filter: session.chatFilterState,
                        search: session.crmSearchQuery,
                        rebuild: rebuildDerivedMessages
                    ))
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
        }
        .animation(.easeInOut(duration: 0.22), value: store.activeComposer)
        .animation(.easeInOut(duration: 0.22), value: previewOrder?.id)
        .animation(.easeInOut(duration: 0.22), value: session.isChatFilterPresented)
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: messageActionsTarget?.id)
        .onChange(of: session.orderComposerRequest) { _, _ in
            // «+» в шапке СРМ открывает ту же форму заказа, что и вложение в чате.
            presentComposer(.order)
        }
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
        .onChange(of: session.activeDocument) { _, document in
            // Проваливание в просмотр заказа/документа из чата — прячем клавиатуру.
            if document != nil {
                dismissKeyboard()
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
        .onChange(of: notificationRouter.pendingRoute) { _, route in
            guard let route else { return }
            handleNotificationRoute(route)
            notificationRouter.pendingRoute = nil
        }
        .onAppear {
            if let route = notificationRouter.pendingRoute {
                handleNotificationRoute(route)
                notificationRouter.pendingRoute = nil
            }
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
            PhotoAttachmentViewer(mediaURL: attachment.mediaURL) {
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
        .modifier(AssemblySplitDialogModifier(
            pending: $pendingAssemblySplit,
            alertMessage: $assemblyAlertMessage,
            onConfirm: { performAssemblySplit($0) }
        ))
        .modifier(OrderCancelDialogModifier(
            pending: $pendingOrderCancel,
            onChoose: { performOrderCancel($0, cancelAllItems: $1) }
        ))
        .task(id: sessionTaskID) {
            // Гейтинг при запуске/смене пользователя: недоступный сохранённый режим → Чат.
            gateInaccessibleMode()
            await store.load(accessToken: session.currentAccessToken, userID: user.userID)
        }
        .task(id: chatStreamTaskID) {
            // Realtime: SSE pushes live changes; the loop also delta-syncs on (re)connect.
            guard scenePhase == .active else { return }
            // Реалтайм-права: при SSE-событии `user_updated` про текущего пользователя
            // перечитываем /me — доступ к режимам/разделам применится на лету (без перезахода).
            store.onUserUpdated = { updatedUserID in
                guard updatedUserID == user.userID else { return }
                Task {
                    await session.refreshCurrentUser()
                    // После обновления прав — сгейтить недоступный текущий режим...
                    gateInaccessibleMode()
                    // ...и перезабрать ленту с нуля: карточки заказов недоступных теперь
                    // складов должны исчезнуть (сервер их уже не отдаёт), а дельта-синк
                    // сам по себе закешированные карточки не удаляет.
                    await store.reloadFeedFromScratch(accessToken: session.currentAccessToken)
                }
            }
            await store.runRealtime(accessToken: session.currentAccessToken)
        }
        .task(id: chatRefreshTaskID) {
            // Fallback poll (cheap delta sync) in case the SSE stream is unavailable. Kept tight
            // so the app stays near-realtime even if SSE can't connect on a given network.
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
                await session.restoreSession()
                await store.reloadMessages(accessToken: session.currentAccessToken)
            }
        }
        .onChange(of: notificationRouter.foregroundPushTick) { _, _ in
            // A push landed while we're open — refresh now so the message appears with the banner.
            Task { await store.reloadMessages(accessToken: session.currentAccessToken) }
        }
    }

    @ViewBuilder
    private func swipeableMainContent(containerWidth: CGFloat) -> some View {
        HomePagingContainer(
            currentPage: currentDisplayMode,
            onSettledPage: { page in
                guard page != currentDisplayMode else { return }
                session.setHomeDisplayMode(page)
            },
            onInteractionBegan: {
                dismissKeyboard()
                // Поле поиска CRM живёт со своим @FocusState в другом вью — снимаем
                // первого ответчика глобально, чтобы клавиатура уезжала сразу на старте
                // свайпа, а не после оседания страницы.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            },
            showChat: showChatPage,
            showCrm: hasCrmAccess,
            showPrice: hasPriceAccess,
            showTodo: hasTodoAccess,
            isPagingDisabled: isTodoSectionBarScrolling,
            chatPage: {
                contentView(for: .chat)
            },
            crmPage: {
                contentView(for: .crm)
            },
            pricePage: {
                contentView(for: .price)
            },
            todoPage: {
                contentView(for: .todo)
            }
        )
    }

    private func contentView(for mode: HomeDisplayMode) -> some View {
        Group {
            switch mode {
            case .chat:
                chatContent
            case .crm:
                crmContent
            case .price:
                PriceSearchView()
            case .todo:
                TodoBoardView(
                    isSectionBarScrolling: $isTodoSectionBarScrolling,
                    // Заказы для привязки берём из той же ленты, что и СРМ: она уже
                    // отфильтрована правами пользователя.
                    orders: crmDocumentMessages.compactMap(\.order),
                    participants: store.participants,
                    externalTodoRevision: store.todoRevision,
                    isVisible: currentDisplayMode == .todo,
                    feedRevision: store.messagesRevision
                )
            }
        }
    }

    // Режим «Прайс» доступен, если пользователь админ, разделы не заданы (null = все),
    // либо в разделах есть 'price'.
    private var hasPriceAccess: Bool { session.hasSectionAccess("price") }

    // Режим «СРМ» доступен: админ, разделы не заданы (null = все), либо есть 'crm'.
    private var hasCrmAccess: Bool { session.hasSectionAccess("crm") }

    // Доступные вкладки СРМ (Все заказы / Товары / Отгрузки) по правам.
    // Админ и null-разделы → все. Если ни один app-ключ не задан в разделах — считаем,
    // что подразделы не сконфигурированы, и показываем все вкладки (обратная совместимость:
    // старым пользователям без app_* ключей не режем СРМ). Иначе — строго по ключам.
    private var allowedCrmSections: [CRMSection] {
        guard let user = session.currentUser else { return CRMSection.allCases }
        if user.userAdmin { return CRMSection.allCases }
        guard let sections = user.userSections else { return CRMSection.allCases }
        let configured = CRMSection.allCases.contains { sections.contains($0.sectionKey) }
        guard configured else { return CRMSection.allCases }
        return CRMSection.allCases.filter { sections.contains($0.sectionKey) }
    }

    // Режим «Задачи» (тудулист) доступен: админ, разделы не заданы (null = все),
    // либо есть 'todo'.
    private var hasTodoAccess: Bool { session.hasSectionAccess("todo") }

    // Режим «Чат» доступен: админ, разделы не заданы (null = все), либо есть 'chat'.
    private var hasChatAccess: Bool { session.hasSectionAccess("chat") }

    // Показывать страницу чата: если раздел выдан — да; сейф-нет — если не выдано ничего
    // (ни СРМ, ни Прайс), всё равно показываем чат, чтобы приложение не осталось пустым.
    private var showChatPage: Bool {
        hasChatAccess || (!hasCrmAccess && !hasPriceAccess && !hasTodoAccess)
    }

    // Первый доступный режим — куда «падать», если текущий стал недоступен.
    private var firstAvailableMode: HomeDisplayMode {
        if showChatPage { return .chat }
        if hasCrmAccess { return .crm }
        if hasPriceAccess { return .price }
        if hasTodoAccess { return .todo }
        return .chat
    }

    /// Если текущий выбранный режим недоступен по правам — перейти на первый доступный.
    /// Зовём при загрузке/смене пользователя и после реалтайм-обновления прав.
    private func gateInaccessibleMode() {
        let accessible: Bool
        switch currentDisplayMode {
        case .chat: accessible = showChatPage
        case .crm: accessible = hasCrmAccess
        case .price: accessible = hasPriceAccess
        case .todo: accessible = hasTodoAccess
        }
        if !accessible {
            session.setHomeDisplayMode(firstAvailableMode)
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if let loadErrorMessage = store.loadErrorMessage {
                Text("Ошибка загрузки чата: \(loadErrorMessage)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.isLoading && store.messages.isEmpty {
                Text("Загружаем историю сообщений...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.mutedText)
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ChatConversationView(
                messages: filteredMessages,
                currentUserID: user.userID,
                mentionNames: store.participants.map(\.displayName),
                participants: store.participants,
                scrollToBottomRequest: scrollToBottomRequest,
                scrollToMessageRequest: scrollToMessageRequest,
                scrollToMessageID: scrollToMessageID,
                highlightedMessageID: highlightedMessageID,
                highlightMessageRequest: replySourceHighlightRequest,
                unreadOrderCommentsCount: { order in
                    store.unreadOrderCommentCount(for: order, currentUserID: user.userID)
                },
                orderCommentReadRevision: store.orderCommentReadRevision,
                onOpenDocument: { kind, id in
                    // Без прав СРМ карточки видны, но открыть просмотр нельзя (как на вебе).
                    guard hasCrmAccess else { return }
                    session.closeChatFilterPanel()
                    previewOrder = nil
                    session.openDocument(kind: kind, id: id)
                },
                onPreviewOrder: { order in
                    guard hasCrmAccess else { return }
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
                    store.messageDraft = message.visibleMessageText
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
                    // Колбэк может прилететь из scrollViewDidScroll во время layout внутри
                    // SwiftUI-апдейта → откладываем запуись @State на следующий тик, иначе
                    // «Modifying state during view update». Лишние записи отсекаем.
                    guard isChatPinnedToBottom != value else { return }
                    DispatchQueue.main.async { isChatPinnedToBottom = value }
                },
                draft: $store.messageDraft,
                isInputFocused: $isMessageFieldFocused,
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var crmContent: some View {
        Group {
            if session.isChecklistOpen {
                CRMChecklistSheet(
                    orders: crmDocumentMessages.compactMap(\.order),
                    establishments: store.referenceData.establishments,
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
                    },
                    onMoveToMovement: { order, item, sourceID, destinationID in
                        let movementStatusID = store.referenceData.statuses.first(where: {
                            $0.statusType == "order_products" && $0.statusStatus == "Перемещение"
                        })?.id

                        guard let movementStatusID else {
                            crmErrorMessage = "Не найден статус Перемещение"
                            return
                        }

                        updateCRMOrderItem(
                            order: order,
                            itemID: item.id,
                            statusID: movementStatusID,
                            sourceEstablishmentID: sourceID,
                            destinationEstablishmentID: destinationID,
                            checkpointStarted: false,
                            checkpointCompleted: false
                        )
                    },
                    itemStatuses: orderItemStatuses,
                    onSelectStatus: { order, item, statusID, supplierName in
                        let isOrdered = orderItemStatuses.first(where: { $0.id == statusID })?.statusStatus == "Заказано"
                        updateCRMOrderItem(
                            order: order,
                            itemID: item.id,
                            statusID: statusID,
                            supplierName: supplierName,
                            checkpointStarted: isOrdered,
                            checkpointCompleted: false
                        )
                    },
                    onSearchSupplierContacts: { query in
                        await store.searchContacts(accessToken: session.currentAccessToken, contactType: "supplier", query: query)
                    }
                )
            } else {
                CRMDocumentsListView(
                    messages: crmDocumentMessages,
                    referenceData: store.referenceData,
                    isLoading: store.isLoading,
                    errorMessage: crmErrorMessage ?? store.loadErrorMessage,
                    updatingDocumentKey: crmUpdatingDocumentKey,
                    selectedSection: $session.crmSection,
                    allowedSections: allowedCrmSections,
                    unreadCommentsCount: { order in
                        guard let userID = session.currentUser?.userID else { return 0 }
                        return store.unreadOrderCommentCount(for: order, currentUserID: userID)
                    },
                    commentReadRevision: store.orderCommentReadRevision,
                    showsTodoBadge: hasTodoAccess,
                    onOpenDocument: { kind, id in
                        session.closeChatFilterPanel()
                        previewOrder = nil
                        session.openDocument(kind: kind, id: id)
                    },
                    onSelectOrderStatus: { order, statusID in
                        updateCRMOrderStatus(order: order, statusID: statusID)
                    },
                    onSelectOrderItemStatus: { order, itemID, statusID, sourceID, destinationID, supplierName in
                        updateCRMOrderItem(
                            order: order,
                            itemID: itemID,
                            statusID: statusID,
                            sourceEstablishmentID: sourceID,
                            destinationEstablishmentID: destinationID,
                            supplierName: supplierName
                        )
                    },
                    onCollectShipmentItem: { order, itemID in
                        updateCRMShipmentItemPacked(order: order, itemID: itemID)
                    },
                    onCollectAllShipmentItems: { order in
                        updateCRMShipmentAllItemsPacked(order: order)
                    },
                    onCompleteShipmentOrder: { order in
                        updateCRMShipmentOrderCompleted(order: order)
                    },
                    onToggleOrderPayment: { order, paid in
                        updateCRMOrderPayment(order: order, paid: paid)
                    },
                    onUpdateOrderItemNote: { order, itemID, note in
                        updateCRMOrderItem(order: order, itemID: itemID, note: note, noteWasProvided: true)
                    },
                    onSearchSupplierContacts: { query in
                        await store.searchContacts(accessToken: session.currentAccessToken, contactType: "supplier", query: query)
                    },
                    onSelectInventoryStatus: { inventory, statusID in
                        updateCRMInventoryStatus(inventory: inventory, statusID: statusID)
                    },
                    onSelectProductRegistrationStatus: { registration, statusID in
                        updateCRMProductRegistrationStatus(registration: registration, statusID: statusID)
                    }
                )
            }
        }
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
                let overscan = proxy.size.height

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.24))
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height + overscan
                    )
                    .offset(y: -overscan)
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
                    store.messageDraft = messageActionsTarget.visibleMessageText
                    isMessageFieldFocused = true
                    self.messageActionsTarget = nil
                },
                onCopy: {
                    UIPasteboard.general.string = messageActionsTarget.visibleMessageText
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
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
                .zIndex(10)
            } else if document.kind == "inventory" {
                InventoryDetailView(store: store, inventoryID: document.id) {
                    session.closeDocument()
                }
                .environmentObject(session)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
                .zIndex(10)
            } else if document.kind == "product_registration" {
                ProductRegistrationDetailView(store: store, productRegistrationID: document.id) {
                    session.closeDocument()
                }
                .environmentObject(session)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .identity))
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
            attachmentErrorMessage = resolveActionError(error)
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
                attachmentErrorMessage = resolveActionError(error)
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

    private func composedEditedText(from text: String, originalMessage: HomeMessage) -> String {
        guard let replyFragment = originalMessage.replyFragment else { return text }
        return "| \(replyFragment.author)\n> \(replyFragment.message)\n\(text)"
    }

    private func submitChatInput() async {
        let trimmedText = store.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if let editingMessage {
            do {
                let updatedText = composedEditedText(from: trimmedText, originalMessage: editingMessage)
                _ = try await store.updateMessage(accessToken: session.currentAccessToken, messageID: editingMessage.id, text: updatedText)
                store.messageDraft = ""
                self.editingMessage = nil
                isMessageFieldFocused = true
            } catch {
            }
            return
        }

        guard let accessToken = session.currentAccessToken else { return }
        let composedText = composedReplyText(from: trimmedText)
        let mentionedUserIDs = MentionEngine.mentionedUserIDs(in: composedText, participants: store.participants)
        replyTarget = nil
        await store.sendMessage(accessToken: accessToken, currentUser: user, text: composedText, clearDraft: true, mentionedUserIDs: mentionedUserIDs)
        isMessageFieldFocused = true
        scrollToBottomRequest += 1
    }

    private func retryFailedMessage(_ message: HomeMessage) async {
        await store.retryFailedMessage(accessToken: session.currentAccessToken, currentUser: user, message: message)
        scrollToBottomRequest += 1
    }

    private func handleNotificationRoute(_ route: NotificationRoute) {
        switch route {
        case let .chatMessage(id):
            session.closeChatFilterPanel()
            session.closeDocument()
            previewOrder = nil
            if session.chatFilterState.displayMode != .chat {
                session.setHomeDisplayMode(.chat)
            }
            scrollToMessageID = id
            scrollToMessageRequest += 1
        case let .order(id):
            previewOrder = nil
            session.openDocument(kind: "order", id: id)
        }
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
            messageActionErrorMessage = resolveActionError(error)
        }
    }

    private func isAssemblyOrderStatus(_ statusID: Int) -> Bool {
        store.referenceData.statuses.first { $0.statusType == "orders" && $0.id == statusID }?.statusStatus == "На сборку"
    }

    private func performAssemblySplit(_ pending: PendingAssemblySplit) {
        Task {
            if pending.isPreview {
                isUpdatingPreviewOrder = true
                previewOrderErrorMessage = nil
            } else {
                crmUpdatingDocumentKey = documentKey(kind: "order", id: pending.order.id)
                crmErrorMessage = nil
            }
            defer {
                if pending.isPreview { isUpdatingPreviewOrder = false } else { crmUpdatingDocumentKey = nil }
            }

            do {
                let updated = try await store.splitOrderForAssembly(accessToken: session.currentAccessToken, order: pending.order)
                // Превью обновляем результатом; CRM-карточки — прилетят realtime по SSE.
                if pending.isPreview { self.previewOrder = updated }
            } catch {
                assemblyAlertMessage = resolveActionError(error)
            }
        }
    }

    private func performOrderCancel(_ pending: PendingOrderCancel, cancelAllItems: Bool) {
        Task {
            if pending.isPreview {
                isUpdatingPreviewOrder = true
                previewOrderErrorMessage = nil
            } else {
                crmUpdatingDocumentKey = documentKey(kind: "order", id: pending.order.id)
                crmErrorMessage = nil
            }
            defer {
                if pending.isPreview { isUpdatingPreviewOrder = false } else { crmUpdatingDocumentKey = nil }
            }

            do {
                let updated = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: pending.order, statusID: pending.statusID, cancelAllItems: cancelAllItems)
                if pending.isPreview { self.previewOrder = updated }
            } catch {
                if pending.isPreview {
                    previewOrderErrorMessage = resolveActionError(error)
                } else {
                    crmErrorMessage = resolveActionError(error)
                }
            }
        }
    }

    private func updatePreviewOrderStatus(statusID: Int) {
        guard let previewOrder else { return }
        guard previewOrder.orderStatusID != statusID else { return }

        if isAssemblyOrderStatus(statusID), store.orderHasPendingItems(previewOrder), store.orderHasCollectableItems(previewOrder) {
            pendingAssemblySplit = PendingAssemblySplit(order: previewOrder, isPreview: true)
            return
        }

        if store.orderStatusName(statusID) == "Отменен", store.orderHasNonCancelledItems(previewOrder) {
            pendingOrderCancel = PendingOrderCancel(order: previewOrder, statusID: statusID, isPreview: true)
            return
        }

        Task {
            isUpdatingPreviewOrder = true
            previewOrderErrorMessage = nil
            defer { isUpdatingPreviewOrder = false }

            do {
                if isAssemblyOrderStatus(statusID) {
                    self.previewOrder = try await store.moveOrderToAssembly(accessToken: session.currentAccessToken, order: previewOrder, assemblyStatusID: statusID)
                } else {
                    self.previewOrder = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: previewOrder, statusID: statusID)
                }
            } catch {
                if isAssemblyOrderStatus(statusID) {
                    assemblyAlertMessage = resolveActionError(error)
                } else {
                    previewOrderErrorMessage = resolveActionError(error)
                }
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
                        orderContactMethod: previewOrder.orderContactMethod,
                        orderSalesChannel: previewOrder.orderSalesChannel,
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
                previewOrderErrorMessage = resolveActionError(error)
            }
        }
    }

    private func updateCRMOrderStatus(order: HomeOrder, statusID: Int) {
        guard order.orderStatusID != statusID else { return }

        if isAssemblyOrderStatus(statusID), store.orderHasPendingItems(order), store.orderHasCollectableItems(order) {
            pendingAssemblySplit = PendingAssemblySplit(order: order, isPreview: false)
            return
        }

        if store.orderStatusName(statusID) == "Отменен", store.orderHasNonCancelledItems(order) {
            pendingOrderCancel = PendingOrderCancel(order: order, statusID: statusID, isPreview: false)
            return
        }

        Task {
            crmUpdatingDocumentKey = documentKey(kind: "order", id: order.id)
            crmErrorMessage = nil
            defer { crmUpdatingDocumentKey = nil }

            do {
                if isAssemblyOrderStatus(statusID) {
                    _ = try await store.moveOrderToAssembly(accessToken: session.currentAccessToken, order: order, assemblyStatusID: statusID)
                } else {
                    _ = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: order, statusID: statusID)
                }
            } catch {
                if isAssemblyOrderStatus(statusID) {
                    assemblyAlertMessage = resolveActionError(error)
                } else {
                    crmErrorMessage = resolveActionError(error)
                }
            }
        }
    }

    /// Отметка «Оплачено» с кнопки у «Итого» (подтверждение показывает список).
    private func updateCRMOrderPayment(order: HomeOrder, paid: Bool) {
        Task {
            crmUpdatingDocumentKey = documentKey(kind: "order", id: order.id)
            crmErrorMessage = nil
            defer { crmUpdatingDocumentKey = nil }

            do {
                _ = try await store.updateOrderPayment(accessToken: session.currentAccessToken, order: order, paid: paid)
            } catch {
                crmErrorMessage = resolveActionError(error)
            }
        }
    }

    private func updateCRMShipmentItemPacked(order: HomeOrder, itemID: Int) {
        updateCRMShipmentItemsPacked(order: order, itemIDs: [itemID])
    }

    /// «Упаковать все» из удержания на кнопке: пакуем все видимые в отгрузке позиции
    /// (отменённые в сборке не участвуют и уже упакованные трогать незачем).
    private func updateCRMShipmentAllItemsPacked(order: HomeOrder) {
        guard let packedItemStatusID = store.referenceData.statuses.first(where: {
            $0.statusType == "order_products" && $0.statusStatus == "Упаковано"
        })?.id else {
            crmErrorMessage = "Не найден статус товара Упаковано"
            return
        }
        let itemIDs = Set(
            order.items
                .filter { !store.isCancelledOrderItem($0) && $0.orderItemStatusID != packedItemStatusID }
                .map(\.id)
        )
        guard !itemIDs.isEmpty else { return }
        updateCRMShipmentItemsPacked(order: order, itemIDs: itemIDs)
    }

    private func updateCRMShipmentItemsPacked(order: HomeOrder, itemIDs: Set<Int>) {
        // Кнопка «Упаковать» в отгрузках переводит позицию в «Упаковано» — финальный
        // шаг сборки: по нему видно, что именно сборщик уже отложил.
        guard let collectedItemStatusID = store.referenceData.statuses.first(where: {
            $0.statusType == "order_products" && $0.statusStatus == "Упаковано"
        })?.id else {
            crmErrorMessage = "Не найден статус товара Упаковано"
            return
        }

        guard let collectedOrderStatusID = store.referenceData.statuses.first(where: {
            $0.statusType == "orders" && $0.statusStatus == "Собран"
        })?.id else {
            crmErrorMessage = "Не найден статус заказа Собран"
            return
        }

        let targetIDs = Set(order.items.filter { itemIDs.contains($0.id) && $0.orderItemStatusID != collectedItemStatusID }.map(\.id))
        guard !targetIDs.isEmpty else { return }

        // Отменённые позиции («Отменен»/«Не будет») не участвуют в сборке — заказ
        // считается собранным, когда упакованы все НЕотменённые товары.
        let allItemsWillBeCollected = order.items.allSatisfy { item in
            store.isCancelledOrderItem(item) || targetIDs.contains(item.id) || item.orderItemStatusID == collectedItemStatusID
        }
        let nextOrderStatusID = allItemsWillBeCollected ? collectedOrderStatusID : order.orderStatusID

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
                        orderContactMethod: order.orderContactMethod,
                        orderSalesChannel: order.orderSalesChannel,
                        orderCustomer: order.orderCustomer,
                        orderInfo: order.orderInfo,
                        orderStatusID: nextOrderStatusID,
                        items: order.items.map { item in
                            makeOrderItemRequest(
                                item: item,
                                statusID: targetIDs.contains(item.id) ? collectedItemStatusID : item.orderItemStatusID,
                                supplierName: item.orderItemSupplier,
                                note: item.orderItemNote,
                                sourceEstablishmentID: item.orderItemSourceEstablishmentID,
                                destinationEstablishmentID: item.orderItemDestinationEstablishmentID,
                                checkpointStarted: item.orderItemCheckpointStarted,
                                checkpointCompleted: item.orderItemCheckpointCompleted
                            )
                        }
                    )
                )
            } catch {
                crmErrorMessage = resolveActionError(error)
            }
        }
    }

    private func updateCRMShipmentOrderCompleted(order: HomeOrder) {
        guard let completedOrderStatusID = store.referenceData.statuses.first(where: {
            $0.statusType == "orders" && $0.statusStatus == "Выполнен"
        })?.id else {
            crmErrorMessage = "Не найден статус заказа Выполнен"
            return
        }

        guard let shippedItemStatusID = store.referenceData.statuses.first(where: {
            $0.statusType == "order_products" && $0.statusStatus == "Отгружено"
        })?.id else {
            crmErrorMessage = "Не найден статус товара Отгружено"
            return
        }

        let requiresUpdate = order.orderStatusID != completedOrderStatusID
            || order.items.contains(where: { !store.isCancelledOrderItem($0) && $0.orderItemStatusID != shippedItemStatusID })

        guard requiresUpdate else { return }

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
                        orderContactMethod: order.orderContactMethod,
                        orderSalesChannel: order.orderSalesChannel,
                        orderCustomer: order.orderCustomer,
                        orderInfo: order.orderInfo,
                        orderStatusID: completedOrderStatusID,
                        items: order.items.map { item in
                            makeOrderItemRequest(
                                item: item,
                                // Отменённые не отгружаем — сохраняют свой статус.
                                statusID: store.isCancelledOrderItem(item) ? item.orderItemStatusID : shippedItemStatusID,
                                supplierName: item.orderItemSupplier,
                                note: item.orderItemNote,
                                sourceEstablishmentID: item.orderItemSourceEstablishmentID,
                                destinationEstablishmentID: item.orderItemDestinationEstablishmentID,
                                checkpointStarted: item.orderItemCheckpointStarted,
                                checkpointCompleted: item.orderItemCheckpointCompleted
                            )
                        }
                    )
                )
            } catch {
                crmErrorMessage = resolveActionError(error)
            }
        }
    }

    private func updateCRMOrderItem(
        order: HomeOrder,
        itemID: Int,
        statusID: Int? = nil,
        sourceEstablishmentID: Int? = nil,
        destinationEstablishmentID: Int? = nil,
        supplierName: String? = nil,
        note: String? = nil,
        noteWasProvided: Bool = false,
        checkpointStarted: Bool? = nil,
        checkpointCompleted: Bool? = nil
    ) {
        guard let currentItem = order.items.first(where: { $0.id == itemID }) else { return }

        let nextStatusID = statusID ?? currentItem.orderItemStatusID
        let nextSourceID = sourceEstablishmentID ?? currentItem.orderItemSourceEstablishmentID
        let nextDestinationID = destinationEstablishmentID ?? currentItem.orderItemDestinationEstablishmentID
        let nextSupplierName = supplierName ?? currentItem.orderItemSupplier
        let nextNote = noteWasProvided ? note : currentItem.orderItemNote
        let didChangeSupplier = normalizedSupplierName(nextSupplierName) != normalizedSupplierName(currentItem.orderItemSupplier)
        let resetCheckpoints = didChangeSupplier || (statusID != nil && statusID != currentItem.orderItemStatusID && shouldResetChecklistState(for: nextStatusID))
        let nextStarted = checkpointStarted ?? (resetCheckpoints ? false : currentItem.orderItemCheckpointStarted)
        let nextCompleted = checkpointCompleted ?? (resetCheckpoints ? false : currentItem.orderItemCheckpointCompleted)

        guard currentItem.orderItemStatusID != nextStatusID
            || currentItem.orderItemSupplier != nextSupplierName
            || currentItem.orderItemNote != nextNote
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
                        orderContactMethod: order.orderContactMethod,
                        orderSalesChannel: order.orderSalesChannel,
                        orderCustomer: order.orderCustomer,
                        orderInfo: order.orderInfo,
                        orderStatusID: order.orderStatusID,
                        items: order.items.map { item in
                            makeOrderItemRequest(
                                item: item,
                                statusID: item.id == itemID ? nextStatusID : item.orderItemStatusID,
                                supplierName: item.id == itemID ? nextSupplierName : item.orderItemSupplier,
                                note: item.id == itemID ? nextNote : item.orderItemNote,
                                noteWasProvided: item.id == itemID ? noteWasProvided : false,
                                sourceEstablishmentID: item.id == itemID ? nextSourceID : item.orderItemSourceEstablishmentID,
                                destinationEstablishmentID: item.id == itemID ? nextDestinationID : item.orderItemDestinationEstablishmentID,
                                checkpointStarted: item.id == itemID ? nextStarted : item.orderItemCheckpointStarted,
                                checkpointCompleted: item.id == itemID ? nextCompleted : item.orderItemCheckpointCompleted
                            )
                        }
                    )
                )
            } catch {
                crmErrorMessage = resolveActionError(error)
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
                crmErrorMessage = resolveActionError(error)
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
                crmErrorMessage = resolveActionError(error)
            }
        }
    }

    private func documentKey(kind: String, id: Int) -> String {
        "\(kind):\(id)"
    }

    private func makeOrderItemRequest(
        item: HomeOrderItem,
        statusID: Int? = nil,
        supplierName: String? = nil,
        note: String? = nil,
        noteWasProvided: Bool = false,
        sourceEstablishmentID: Int? = nil,
        destinationEstablishmentID: Int? = nil,
        checkpointStarted: Bool? = nil,
        checkpointCompleted: Bool? = nil
    ) -> HomeOrderItemCreateRequest {
        HomeOrderItemCreateRequest(
            productID: item.orderItemProductID,
            productArticle: item.orderItemArticle,
            productName: item.orderItemName,
            orderItemQuantity: item.orderItemQuantity,
            orderItemPrice: item.orderItemPrice,
            orderItemStatusID: statusID ?? item.orderItemStatusID,
            orderItemSupplier: supplierName ?? item.orderItemSupplier,
            orderItemNote: noteWasProvided ? note : (note ?? item.orderItemNote),
            orderItemSourceEstablishmentID: sourceEstablishmentID ?? item.orderItemSourceEstablishmentID,
            orderItemDestinationEstablishmentID: destinationEstablishmentID ?? item.orderItemDestinationEstablishmentID,
            orderItemCurrencyID: item.orderItemCurrencyID,
            orderItemCheckpointStarted: checkpointStarted ?? item.orderItemCheckpointStarted,
            orderItemCheckpointCompleted: checkpointCompleted ?? item.orderItemCheckpointCompleted
        )
    }

    private func normalizedSupplierName(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func shouldResetChecklistState(for statusID: Int?) -> Bool {
        guard let statusID else { return false }
        guard let status = store.referenceData.statuses.first(where: { $0.id == statusID }) else { return false }
        return status.statusType == "order_products" && ["Заказ поставщику", "Перемещение"].contains(status.statusStatus)
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

        if kind == .order, !filter.orderMethodIDs.isEmpty {
            guard let orderMethodID = message.filterOrderMethodID,
                  filter.orderMethodIDs.contains(orderMethodID) else {
                return false
            }
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

        if kind != .message
            && filter.hideCancelled
            && isCancelledMessage(message)
            && !isExplicitlySelectedCancelledStatus(message.filterStatusID, in: filter.statusIDs) {
            return false
        }

        return true
    }

    private func matchesCRMSearch(_ message: HomeMessage) -> Bool {
        let query = normalizedCRMSearchQuery
        guard !query.isEmpty else { return true }
        guard let order = message.order else { return true }

        let searchableParts = [
            String(order.id),
            order.orderCustomer,
            order.orderEstablishmentName ?? "",
            order.orderInfo,
            order.items.map(\.orderItemName).joined(separator: " "),
            order.items.compactMap(\.orderItemArticle).joined(separator: " ")
        ]

        let haystack = searchableParts
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()

        let normalizedQuery = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()

        return haystack.contains(normalizedQuery)
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

    private func isExplicitlySelectedCancelledStatus(_ statusID: Int?, in selectedStatusIDs: Set<Int>) -> Bool {
        guard let statusID, selectedStatusIDs.contains(statusID) else { return false }
        guard let status = store.referenceData.statuses.first(where: { $0.id == statusID }) else { return false }
        return isCancelledStatusTitle(status.statusStatus)
    }

    private func isCancelledMessage(_ message: HomeMessage) -> Bool {
        guard message.filterKind != .message else { return false }
        return isCancelledStatusTitle(message.filterStatusText)
    }

    private func isCancelledStatusTitle(_ statusTitle: String?) -> Bool {
        let normalizedStatus = (statusTitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedStatus.isEmpty else { return false }
        return normalizedStatus.contains("отмен")
            || normalizedStatus.contains("cancel")
    }

    @ViewBuilder
    private func composerOverlay(for composer: HomeComposerKind) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()

                ComposerSheetView(kind: composer, store: store) {
                    store.activeComposer = nil
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: proxy.size.height * 0.9)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: -4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                // Светлый экран создания (фон + тёмный читаемый текст) в тёмном приложении.
                .environment(\.colorScheme, .light)
            }
        }
    }
}

private struct HomePagingContainer<ChatPage: View, CRMPage: View, PricePage: View, TodoPage: View>: View {
    let currentPage: HomeDisplayMode
    let onSettledPage: (HomeDisplayMode) -> Void
    var onInteractionBegan: () -> Void = {}
    let showChat: Bool
    let showCrm: Bool
    let showPrice: Bool
    let showTodo: Bool
    /// Временный запрет листания: страница просит не перехватывать её жест.
    var isPagingDisabled: Bool = false
    @ViewBuilder let chatPage: () -> ChatPage
    @ViewBuilder let crmPage: () -> CRMPage
    @ViewBuilder let pricePage: () -> PricePage
    @ViewBuilder let todoPage: () -> TodoPage

    @State private var activePage: HomeDisplayMode?
    @State private var pendingPage: HomeDisplayMode?

    // Сигнатура набора видимых страниц: меняется при выдаче/отзыве раздела.
    private var pageSignature: String { "\(showChat)-\(showCrm)-\(showPrice)-\(showTodo)" }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ScrollView(.horizontal) {
                // Порядок страниц: Прайс → Чат → СРМ → Задачи.
                HStack(spacing: 0) {
                    if showPrice {
                        pricePage()
                            .frame(width: width)
                            .id(HomeDisplayMode.price)
                    }

                    if showChat {
                        chatPage()
                            .frame(width: width)
                            .id(HomeDisplayMode.chat)
                    }

                    if showCrm {
                        crmPage()
                            .frame(width: width)
                            .id(HomeDisplayMode.crm)
                    }

                    if showTodo {
                        todoPage()
                            .frame(width: width)
                            .id(HomeDisplayMode.todo)
                    }
                }
                .scrollTargetLayout()
                // Гасим rubber-band оверскролл ТОЛЬКО у этого (горизонтального) пейджера,
                // чтобы по краям не появлялся пустой горизонтальный «паддинг».
                // Не используем глобальный UIScrollView.appearance().bounces — он бы убил
                // вертикальный bounce у списка чата и всех остальных скроллов.
                .background(PagerBounceDisabler())
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollDisabled(isPagingDisabled)
            .scrollPosition(id: $activePage)
            .onScrollPhaseChange { _, newPhase in
                // Как только распознано боковое движение пальца — закрываем клавиатуру,
                // чтобы она уезжала вместе с началом свайпа, а не после перелистывания.
                if newPhase == .interacting {
                    onInteractionBegan()
                }
                guard newPhase == .idle,
                      let pendingPage,
                      pendingPage != currentPage else {
                    return
                }
                onSettledPage(pendingPage)
            }
            .onChange(of: activePage) { _, page in
                guard let page else { return }
                pendingPage = page
            }
            .onChange(of: currentPage) { _, page in
                pendingPage = page
                guard activePage != page else { return }
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                    activePage = page
                }
            }
            .onChange(of: pageSignature) { _, _ in
                // Набор доступных страниц изменился (выдали/забрали раздел). Переякориваем
                // пейджер на ТЕКУЩИЙ режим, чтобы вставка/удаление страницы слева не сдвигала
                // экран (при добавлении прав пользователь остаётся там, где был).
                let target = currentPage
                activePage = target
                pendingPage = target
                DispatchQueue.main.async { activePage = target }
            }
            .onAppear {
                activePage = currentPage
                pendingPage = currentPage
            }
        }
    }
}

/// Находит ближайший вышестоящий UIScrollView (горизонтальный пейджер) и отключает у него
/// bounce. Scoped: затрагивает только пейджер, в котором размещён, не глобально.
private struct PagerBounceDisabler: UIViewRepresentable {
    final class Coordinator {
        var applied = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async { Self.disableBounce(from: view, coordinator: context.coordinator) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Применяем один раз — без повторного обхода иерархии на каждом обновлении.
        guard !context.coordinator.applied else { return }
        DispatchQueue.main.async { Self.disableBounce(from: uiView, coordinator: context.coordinator) }
    }

    private static func disableBounce(from view: UIView, coordinator: Coordinator) {
        guard !coordinator.applied else { return }
        var candidate = view.superview
        while let current = candidate {
            if let scrollView = current as? UIScrollView {
                scrollView.bounces = false
                scrollView.alwaysBounceHorizontal = false
                coordinator.applied = true
                return
            }
            candidate = current.superview
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
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var canReply: Bool {
        !message.isLocalOnly
    }

    private var canEdit: Bool {
        message.documentKind == nil && message.attachments.isEmpty && message.messageType == "message" && message.deliveryState == .sent
    }

    private var canCopy: Bool {
        // Только текст: без карточек-документов и без вложений, и есть что копировать.
        message.documentKind == nil && message.attachments.isEmpty && !message.visibleMessageText.isEmpty
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

            if canCopy {
                if canReply || canEdit {
                    menuDivider
                }
                MessageActionButton(title: "Скопировать", action: onCopy)
            }

            if canDelete {
                if canReply || canEdit || canCopy {
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
    let onCopy: () -> Void
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
                    onCopy: onCopy,
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

                    Text(documentSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
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
            if let documentID = message.documentID {
                return "Заказ №\(documentID)"
            }
            return "Заказ"
        case "inventory":
            return "Инвентаризация"
        case "product_registration":
            return "Приемка"
        default:
            return "Документ"
        }
    }

    private var documentSubtitle: String {
        if message.documentKind == "order" {
            let establishment = orderEstablishmentTitle
            let orderCustomer = orderCustomerTitle

            if !orderCustomer.isEmpty {
                return "\(establishment) * \(orderCustomer)"
            }
            return establishment
        }

        if message.documentKind == "inventory" {
            return inventoryEstablishmentTitle
        }

        if message.documentKind == "product_registration" {
            let establishment = productRegistrationEstablishmentTitle
            let supplier = productRegistrationSupplierTitle

            if !supplier.isEmpty {
                return "\(establishment) * \(supplier)"
            }
            return establishment
        }

        if let documentID = message.documentID {
            return "document_id: \(documentID)"
        }

        return ""
    }

    private var orderCustomerTitle: String {
        if let orderCustomer = message.order?.orderCustomer.trimmingCharacters(in: .whitespacesAndNewlines), !orderCustomer.isEmpty {
            return orderCustomer
        }

        guard let messageText = message.messageText else { return "" }
        let firstSegment = messageText
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstSegment
    }

    private var orderEstablishmentTitle: String {
        if let establishment = message.order?.orderEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines), !establishment.isEmpty {
            return establishment
        }
        return "Точка"
    }

    private var inventoryEstablishmentTitle: String {
        if let establishment = message.inventory?.inventoryEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines), !establishment.isEmpty {
            return establishment
        }
        return "Точка"
    }

    private var productRegistrationEstablishmentTitle: String {
        if let establishment = message.productRegistration?.productRegistrationEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines), !establishment.isEmpty {
            return establishment
        }
        return "Точка"
    }

    private var productRegistrationSupplierTitle: String {
        if let supplier = message.productRegistration?.productRegistrationSupplier?.trimmingCharacters(in: .whitespacesAndNewlines), !supplier.isEmpty {
            return supplier
        }

        guard let messageText = message.messageText else { return "" }
        let firstSegment = messageText
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstSegment
    }

    private var statusBackgroundColor: Color {
        BusinessDocumentColors.statusColor(message.messageStatusColor)
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
                userCreatedAt: nil,
                userEstablishmentRoles: nil,
                userSections: nil
            )
        )
    }
    .environmentObject(AppSession())
}
