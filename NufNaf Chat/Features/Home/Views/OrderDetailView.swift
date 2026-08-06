import SwiftUI
import UIKit

struct OrderDetailView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var store: HomeStore
    @FocusState private var isCommentFieldFocused: Bool

    let orderID: Int
    let onClose: () -> Void

    init(store: HomeStore, orderID: Int, onClose: @escaping () -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.orderID = orderID
        self.onClose = onClose
        // Seed from the feed cache so the full card (items, prices) is on screen during the open
        // animation; loadOrder() then refreshes it (and pulls comments).
        _order = State(initialValue: store.cachedOrder(orderID: orderID))
    }

    @State private var order: HomeOrder?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isEditSheetPresented = false
    @State private var comments: [HomeOrderComment] = []
    @State private var commentDraft = ""
    @State private var commentReplyTarget: HomeOrderComment?
    @State private var commentEditTarget: HomeOrderComment?
    @State private var isSendingComment = false
    @State private var isCommentAttachmentMenuPresented = false
    @State private var movementSelection: OrderItemMovementSelection?
    @State private var isPhotoLibraryPresented = false
    @State private var isCameraPresented = false
    @State private var isFilePickerPresented = false
    @State private var attachmentErrorMessage: String?
    @State private var localFilePreview: LocalAttachmentPreview?
    @State private var activePhotoAttachment: HomeOrderCommentAttachment?
    @State private var pendingCommentPayloads: [Int: PendingOrderCommentPayload] = [:]
    @State private var assemblySplitStatusID: Int?
    @State private var pendingCancelStatusID: Int?
    @State private var assemblyAlertMessage: String?
    @State private var commentScrollRequest = 0
    @State private var cdekSheetOrder: HomeOrder?
    @State private var cdekOverride: HomeOrderCdek?
    @State private var didCopyTrack = false
    @State private var cdekRecreating = false
    @State private var cdekRecreateConfirm = false
    // Mirrors the detail container's slide offset so the comment dock (a safeAreaInset, outside the
    // container) slides out together with the card on close instead of lingering.
    @State private var dockOffsetX: CGFloat = 0

    private enum PendingOrderCommentPayload {
        case text(String)
        case attachment(PickedChatAttachment, URL)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            contentView

            if let movementSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.movementSelection = nil
                    }
                    .zIndex(20)

                OrderItemMovementRouteSheet(
                    establishments: store.referenceData.establishments,
                    initialSourceEstablishmentID: movementSelection.sourceEstablishmentID,
                    initialDestinationEstablishmentID: movementSelection.destinationEstablishmentID,
                    onClose: {
                        self.movementSelection = nil
                    },
                    onConfirm: { sourceID, destinationID in
                        updateItemStatus(
                            itemID: movementSelection.itemID,
                            statusID: movementSelection.statusID,
                            sourceEstablishmentID: sourceID,
                            destinationEstablishmentID: destinationID
                        )
                        self.movementSelection = nil
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(21)
            }

        }
        .animation(.easeInOut(duration: 0.18), value: isCommentAttachmentMenuPresented)
        .task(id: orderID) {
            await loadOrder()
            // Авто-обновление статуса СДЭК при открытии заказа (если накладная уже создана).
            if let oid = order?.id, order?.cdek?.hasWaybill == true,
               let upd = try? await store.cdekWaybillStatus(accessToken: session.currentAccessToken, orderID: oid) {
                cdekOverride = upd
            }
        }
        .alert("Пересоздать накладную СДЭК?", isPresented: $cdekRecreateConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Сбросить и создать заново", role: .destructive) {
                if let order { recreateCdek(order: order) }
            }
        } message: {
            Text("Текущая накладная будет удалена в СДЭК. Данные получателя сохранятся — форма откроется заново.")
        }
        .alert(
            "Нельзя перевести в «На сборку»",
            isPresented: Binding(get: { assemblyAlertMessage != nil }, set: { if !$0 { assemblyAlertMessage = nil } })
        ) {
            Button("Понятно", role: .cancel) { assemblyAlertMessage = nil }
        } message: {
            Text(assemblyAlertMessage ?? "")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if order != nil {
                commentComposerDock
                    .environment(\.colorScheme, .light)
                    .offset(x: dockOffsetX) // slide out together with the card on close
            }
        }
        // Оверлей редактирования — поверх всего экрана (включая док комментариев),
        // чтобы выезжал от нижнего края, как при создании заказа.
        .overlay {
            if let order, isEditSheetPresented {
                orderEditOverlay(order: order)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isEditSheetPresented)
        // Подтверждения (сплит на сборку / отмена заказа) — карточкой поверх всего.
        .overlay {
            if assemblySplitStatusID != nil {
                AppConfirmCard(
                    title: "Разделить заказ?",
                    message: "В заказе есть товары не в наличии. «В наличии» уйдут на сборку, остальные — в новый заказ (дубль).",
                    buttons: [
                        AppConfirmButton(label: "Разделить и на сборку", style: .primary) {
                            assemblySplitStatusID = nil
                            performAssemblySplit()
                        },
                        AppConfirmButton(label: "Отмена", style: .cancel) { assemblySplitStatusID = nil },
                    ]
                )
                .transition(.opacity)
            } else if let statusID = pendingCancelStatusID {
                AppConfirmCard(
                    title: "Отменить заказ",
                    message: "Отменить и все товары заказа, или оставить их текущие статусы?",
                    buttons: [
                        AppConfirmButton(label: "Отменить и все товары", style: .destructive) {
                            pendingCancelStatusID = nil
                            performOrderCancel(statusID: statusID, cancelAllItems: true)
                        },
                        AppConfirmButton(label: "Оставить статусы товаров", style: .primary) {
                            pendingCancelStatusID = nil
                            performOrderCancel(statusID: statusID, cancelAllItems: false)
                        },
                        AppConfirmButton(label: "Отмена", style: .cancel) { pendingCancelStatusID = nil },
                    ]
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: assemblySplitStatusID)
        .animation(.easeInOut(duration: 0.18), value: pendingCancelStatusID)
        .onChange(of: isEditSheetPresented) { _, isPresented in
            if isPresented {
                closeCommentAttachmentMenu()
                dismissCommentKeyboard()
            }
        }
        // Скролл к чату на фокус не дёргаем — его делает единый обработчик появления
        // клавиатуры (в скаффолде), иначе две анимации компаундятся и подъём «тянет».
        .onChange(of: isCommentAttachmentMenuPresented) { _, isPresented in
            guard isPresented || isCommentFieldFocused else { return }
            commentScrollRequest += 1
        }
        .sheet(isPresented: $isPhotoLibraryPresented) {
            PhotoLibraryAttachmentPicker(
                onPick: { attachment in
                    isPhotoLibraryPresented = false
                    handlePickedCommentAttachment(attachment)
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
                    handlePickedCommentAttachment(attachment)
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
                    handlePickedCommentAttachment(attachment)
                },
                onCancel: {
                    isFilePickerPresented = false
                }
            )
        }
        .sheet(item: $localFilePreview) { preview in
            LocalFileQuickLookPreview(fileURL: preview.url)
        }
        .sheet(item: $cdekSheetOrder) { snapshot in
            CdekWaybillSheet(order: snapshot, store: store, accessToken: session.currentAccessToken, onCreated: afterCdekWaybillCreated)
        }
        .fullScreenCover(item: $activePhotoAttachment) { attachment in
            OrderCommentPhotoViewer(attachment: attachment) {
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
    }

    private var contentView: some View {
        BusinessDocumentDetailContainer(
            title: "Заказ №\(orderID)",
            isLoading: isLoading,
            isSaving: isSaving,
            errorMessage: errorMessage,
            dockOffset: $dockOffsetX,
            onClose: onClose,
            onInteractiveDismissStart: {
                dismissCommentKeyboard()
                closeCommentAttachmentMenu()
            },
            headerActionSystemImage: order == nil ? nil : "pencil",
            onHeaderAction: order == nil ? nil : { isEditSheetPresented = true },
            prefersDarkHeader: true,
            scrollTargetID: "order-comments-section",
            scrollRequest: commentScrollRequest,
            contentHorizontalPadding: 0,
            headerContent: {
                if let order {
                    BusinessDocumentStatusButtons(
                        statuses: orderStatuses,
                        selectedStatusID: order.orderStatusID,
                        isSaving: isSaving,
                        prefersDarkAppearance: true,
                        onSelect: updateStatus
                    )
                }
            },
            content: {
                if let order {
                    VStack(spacing: 16) {
                        BusinessDocumentInfoSection(
                            title: "Параметры",
                            rows: infoRows(for: order),
                            labelWidth: 108
                        )

                        if isCdekOrder(order) {
                            cdekBlock(order: order)
                        }

                        OrderDocumentItemsSection(
                            title: "Позиции",
                            items: order.items.map {
                                OrderDocumentItemViewModel(
                                    id: $0.id,
                                    name: $0.orderItemName,
                                    statusTitle: orderItemStatusTitle(for: $0),
                                    statusColor: orderItemStatusColor(for: $0),
                                    selectedStatusID: $0.orderItemStatusID,
                                    statuses: orderItemStatuses,
                                    quantity: "\($0.orderItemQuantity)",
                                    price: $0.orderItemPrice,
                                    currencyTitle: currencyTitle(for: $0.orderItemCurrencyID),
                                    quantityValue: $0.orderItemQuantity,
                                    priceValue: parseOrderItemPrice($0.orderItemPrice)
                                )
                            },
                            isSaving: isSaving,
                            onSelectStatus: handleItemStatusSelection
                        )

                        OrderCommentsSection(
                            comments: comments,
                            currentUserID: session.currentUser?.userID,
                            currentUserIsAdmin: session.currentUser?.userAdmin ?? false,
                            mentionNames: store.participants.map(\.displayName),
                            isComposerActive: isCommentFieldFocused || isCommentAttachmentMenuPresented,
                            onOpenAttachment: openAttachment,
                            onRetryComment: retryFailedComment,
                            onReplyComment: startReplyToComment,
                            onEditComment: startEditComment,
                            onCopyComment: copyComment,
                            onDeleteComment: deleteComment,
                            onBackgroundTap: {
                                dismissCommentKeyboard()
                                closeCommentAttachmentMenu()
                            }
                        )
                        .id("order-comments-section")
                    }
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            dismissCommentKeyboard()
            closeCommentAttachmentMenu()
        }
    }

    private var commentComposerDock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCommentAttachmentMenuPresented {
                OrderCommentAttachmentMenu(
                    onPhotoTap: { presentAttachmentAction(kind: "Фото") },
                    onCameraTap: { presentAttachmentAction(kind: "Камера") },
                    onFileTap: { presentAttachmentAction(kind: "Файл") }
                )
                .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity), removal: .opacity))
                .padding(.leading, 8)
            }

            if !commentMentionSuggestions.isEmpty {
                MentionSuggestionsView(participants: commentMentionSuggestions) { participant in
                    commentDraft = MentionEngine.insertMention(participant, into: commentDraft)
                    isCommentFieldFocused = true
                }
            }

            if commentEditTarget != nil {
                OrderCommentComposeBanner(
                    title: "Редактирование",
                    author: nil,
                    snippet: commentDraft,
                    onCancel: { cancelCommentEdit() }
                )
            } else if let commentReplyTarget {
                OrderCommentComposeBanner(
                    title: "Ответ",
                    author: commentReplyTarget.displayName,
                    snippet: commentReplyTarget.replyReferenceText,
                    onCancel: { self.commentReplyTarget = nil }
                )
            }

            OrderCommentInputPanel(
                text: $commentDraft,
                isTextFieldFocused: $isCommentFieldFocused,
                isSending: isSendingComment,
                onAttach: {
                    dismissCommentKeyboard()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        isCommentAttachmentMenuPresented.toggle()
                    }
                },
                onSend: {
                    Task {
                        await sendComment()
                    }
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemBackground).shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: -4))
    }

    private var commentMentionSuggestions: [ChatParticipant] {
        guard isCommentFieldFocused, let query = MentionEngine.activeQuery(in: commentDraft) else { return [] }
        return MentionEngine.suggestions(from: store.participants, query: query, excludingUserID: session.currentUser?.userID)
    }

    private var orderStatuses: [HomeStatus] {
        // «Собран»/«Выполнен» ставятся только флоу отгрузки — убираем из ручного
        // селекта. Текущий статус заказа оставляем, чтобы он отображался как выбранный.
        let hidden: Set<String> = ["Собран", "Выполнен"]
        let currentID = order?.orderStatusID
        return store.referenceData.statuses.filter {
            $0.statusType == "orders" && (!hidden.contains($0.statusStatus) || $0.id == currentID)
        }
    }

    private var orderItemStatuses: [HomeStatus] {
        store.referenceData.statuses.filter { $0.statusType == "order_products" }
    }

    private func editingItemStatusIDs(for order: HomeOrder) -> [Int: Int?] {
        Dictionary(uniqueKeysWithValues: order.items.map { ($0.id, $0.orderItemStatusID) })
    }

    private func orderEditOverlay(order: HomeOrder) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditSheetPresented = false
                    }

                ComposerSheetView(
                    kind: .order,
                    editingOrder: order,
                    editingItemStatusIDs: editingItemStatusIDs(for: order),
                    store: store,
                    onClose: {
                        isEditSheetPresented = false
                    },
                    onOrderUpdated: { updatedOrder in
                        self.order = updatedOrder
                        self.comments = sortComments(updatedOrder.comments)
                        markCommentsRead(updatedOrder.comments)
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: proxy.size.height * 0.9)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: -4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                // Светлый экран редактирования (как при создании заказа) в тёмном приложении.
                .environment(\.colorScheme, .light)
            }
        }
    }

    private func loadOrder() async {
        // If the order is already on screen (seeded from cache), refresh silently so the content
        // doesn't blink to a loading spinner — only show the spinner on a true cold open.
        let showSpinner = order == nil
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { if showSpinner { isLoading = false } }

        do {
            let loadedOrder = try await store.fetchOrder(accessToken: session.currentAccessToken, orderID: orderID)
            order = loadedOrder
            comments = sortComments(loadedOrder.comments)
            markCommentsRead(loadedOrder.comments)
        } catch {
            errorMessage = resolveActionError(error)
        }
    }

    private func updateStatus(_ statusID: Int) {
        guard let order else { return }
        guard order.orderStatusID != statusID else { return }

        let targetName = orderStatuses.first(where: { $0.id == statusID })?.statusStatus
            ?? store.referenceData.statuses.first(where: { $0.statusType == "orders" && $0.id == statusID })?.statusStatus

        // Смешанный заказ (есть и «В наличии», и ожидаемые) — предлагаем сплит.
        if targetName == "На сборку", store.orderHasPendingItems(order), store.orderHasCollectableItems(order) {
            assemblySplitStatusID = statusID
            return
        }

        // Отмена заказа — предлагаем отменить и все товары.
        if targetName == "Отменен", store.orderHasNonCancelledItems(order) {
            pendingCancelStatusID = statusID
            return
        }

        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                let updatedOrder: HomeOrder
                if targetName == "На сборку" {
                    // Гейт (все товары в наличии/отменены) + конверсия «Не будет»→«Отменен».
                    updatedOrder = try await store.moveOrderToAssembly(accessToken: session.currentAccessToken, order: order, assemblyStatusID: statusID)
                } else {
                    updatedOrder = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: order, statusID: statusID)
                }
                self.order = updatedOrder
                self.comments = sortComments(updatedOrder.comments)
                markCommentsRead(updatedOrder.comments)
            } catch {
                // Ошибку гейта «На сборку» показываем оверлейным алертом.
                if targetName == "На сборку" {
                    assemblyAlertMessage = resolveActionError(error)
                } else {
                    errorMessage = resolveActionError(error)
                }
            }
        }
    }

    private func performAssemblySplit() {
        guard let order else { return }
        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                // «В наличии» → этот заказ в «На сборку», остальное → новый заказ-дубль.
                let updatedOrder = try await store.splitOrderForAssembly(accessToken: session.currentAccessToken, order: order)
                self.order = updatedOrder
                self.comments = sortComments(updatedOrder.comments)
                markCommentsRead(updatedOrder.comments)
            } catch {
                assemblyAlertMessage = resolveActionError(error)
            }
        }
    }

    private func performOrderCancel(statusID: Int, cancelAllItems: Bool) {
        guard let order else { return }
        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                let updatedOrder = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: order, statusID: statusID, cancelAllItems: cancelAllItems)
                self.order = updatedOrder
                self.comments = sortComments(updatedOrder.comments)
                markCommentsRead(updatedOrder.comments)
            } catch {
                errorMessage = resolveActionError(error)
            }
        }
    }

    private func handleItemStatusSelection(itemID: Int, statusID: Int) {
        guard let order else { return }
        guard let item = order.items.first(where: { $0.id == itemID }) else { return }
        guard item.orderItemStatusID != statusID else { return }

        if orderItemStatuses.first(where: { $0.id == statusID })?.statusStatus == "Перемещение" {
            movementSelection = OrderItemMovementSelection(
                itemID: itemID,
                statusID: statusID,
                sourceEstablishmentID: item.orderItemSourceEstablishmentID,
                destinationEstablishmentID: item.orderItemDestinationEstablishmentID
            )
            return
        }

        updateItemStatus(itemID: itemID, statusID: statusID)
    }

    private func updateItemStatus(
        itemID: Int,
        statusID: Int,
        sourceEstablishmentID: Int? = nil,
        destinationEstablishmentID: Int? = nil
    ) {
        guard let order else { return }
        guard let currentItem = order.items.first(where: { $0.id == itemID }) else { return }

        let nextSourceID = sourceEstablishmentID ?? currentItem.orderItemSourceEstablishmentID
        let nextDestinationID = destinationEstablishmentID ?? currentItem.orderItemDestinationEstablishmentID
        let resetCheckpoints = shouldResetChecklistState(for: statusID)

        guard currentItem.orderItemStatusID != statusID
            || currentItem.orderItemSourceEstablishmentID != nextSourceID
            || currentItem.orderItemDestinationEstablishmentID != nextDestinationID else {
            return
        }

        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                let updatedOrder = try await store.updateOrder(
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
                                statusID: item.id == itemID ? statusID : item.orderItemStatusID,
                                sourceEstablishmentID: item.id == itemID ? nextSourceID : item.orderItemSourceEstablishmentID,
                                destinationEstablishmentID: item.id == itemID ? nextDestinationID : item.orderItemDestinationEstablishmentID,
                                checkpointStarted: item.id == itemID && resetCheckpoints ? false : item.orderItemCheckpointStarted,
                                checkpointCompleted: item.id == itemID && resetCheckpoints ? false : item.orderItemCheckpointCompleted
                            )
                        }
                    )
                )
                self.order = updatedOrder
                self.comments = sortComments(updatedOrder.comments)
                markCommentsRead(updatedOrder.comments)
            } catch {
                errorMessage = resolveActionError(error)
            }
        }
    }

    private func sendComment() async {
        let trimmedText = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Режим редактирования: обновляем существующий комментарий на сервере,
        // сохраняя reply-префикс исходного сообщения.
        if let editTarget = commentEditTarget {
            let composedText = composedEditedCommentText(from: trimmedText, original: editTarget)
            commentDraft = ""
            commentEditTarget = nil
            do {
                let mentionedUserIDs = MentionEngine.mentionedUserIDs(in: composedText, participants: store.participants)
                let updated = try await store.updateOrderComment(accessToken: session.currentAccessToken, orderID: orderID, commentID: editTarget.id, text: composedText, mentionedUserIDs: mentionedUserIDs)
                replaceComment(localID: editTarget.id, with: updated)
            } catch {
                errorMessage = resolveActionError(error)
            }
            return
        }

        // Ответ на сообщение кодируем текстовым префиксом (как в основном чате):
        // «| Автор\n> цитата\nтело». Бэкенд про reply не знает.
        let composedText = composedCommentReplyText(from: trimmedText)
        commentReplyTarget = nil

        let localCommentID = nextLocalCommentID()
        let localComment = HomeOrderComment.makeLocalTextComment(
            id: localCommentID,
            orderID: orderID,
            text: composedText,
            user: currentUser,
            deliveryState: .pending
        )
        pendingCommentPayloads[localCommentID] = .text(composedText)
        mergeComment(localComment)
        requestCommentScrollToBottom()
        commentDraft = ""
        errorMessage = nil
        isSendingComment = false

        await finishSendingComment(localCommentID: localCommentID, payload: .text(composedText))
    }

    private func composedCommentReplyText(from text: String) -> String {
        guard let commentReplyTarget else { return text }
        return "| \(commentReplyTarget.displayName)\n> \(commentReplyTarget.replyReferenceText)\n\(text)"
    }

    private func startReplyToComment(_ comment: HomeOrderComment) {
        commentEditTarget = nil
        commentReplyTarget = comment
        closeCommentAttachmentMenu()
        isCommentFieldFocused = true
        requestCommentScrollToBottom()
    }

    private func startEditComment(_ comment: HomeOrderComment) {
        commentReplyTarget = nil
        commentEditTarget = comment
        commentDraft = comment.visibleText
        closeCommentAttachmentMenu()
        isCommentFieldFocused = true
        requestCommentScrollToBottom()
    }

    private func cancelCommentEdit() {
        commentEditTarget = nil
        commentDraft = ""
    }

    private func composedEditedCommentText(from text: String, original: HomeOrderComment) -> String {
        guard let reply = original.replyFragment else { return text }
        return "| \(reply.author)\n> \(reply.message)\n\(text)"
    }

    private func copyComment(_ comment: HomeOrderComment) {
        let text = comment.visibleText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    private func sortComments(_ comments: [HomeOrderComment]) -> [HomeOrderComment] {
        comments.sorted {
            switch ($0.parsedCreatedAt, $1.parsedCreatedAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return $0.id < $1.id
            }
        }
    }

    private func markCommentsRead(_ comments: [HomeOrderComment]) {
        guard let userID = session.currentUser?.userID else { return }
        store.markOrderCommentsRead(orderID: orderID, comments: comments, userID: userID)
    }

    private func closeCommentAttachmentMenu() {
        withAnimation(.easeOut(duration: 0.16)) {
            isCommentAttachmentMenuPresented = false
        }
    }

    private func dismissCommentKeyboard() {
        isCommentFieldFocused = false
    }

    private func presentAttachmentAction(kind: String) {
        closeCommentAttachmentMenu()
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

    private var currentUser: AuthUser {
        session.currentUser ?? AuthUser(
            userID: 0,
            userLogin: "",
            userAdmin: false,
            userActive: true,
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
    }

    private func nextLocalCommentID() -> Int {
        min(-1, (comments.map(\.id).min() ?? 0) - 1)
    }

    private func mergeComment(_ comment: HomeOrderComment) {
        if let index = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[index] = comment
        } else {
            comments.append(comment)
        }
        comments = sortComments(comments)
    }

    private func requestCommentScrollToBottom() {
        DispatchQueue.main.async {
            commentScrollRequest += 1
        }
    }

    private func replaceComment(localID: Int, with comment: HomeOrderComment) {
        comments.removeAll { $0.id == localID }
        pendingCommentPayloads.removeValue(forKey: localID)
        mergeComment(comment)
        markCommentsRead(comments)
        requestCommentScrollToBottom()
    }

    private func updateCommentState(commentID: Int, deliveryState: HomeMessageDeliveryState) {
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else { return }
        comments[index].deliveryState = deliveryState
        comments = sortComments(comments)
    }

    private func handlePickedCommentAttachment(_ attachment: PickedChatAttachment) {
        Task {
            do {
                let localFileURL = try store.persistOrderCommentAttachmentToTemporaryURL(data: attachment.data, filename: attachment.filename)
                let localCommentID = nextLocalCommentID()
                let localAttachment = HomeOrderCommentAttachment.makeLocal(
                    id: localCommentID,
                    kind: attachment.attachmentKind,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    sizeBytes: attachment.data.count,
                    localFileURL: localFileURL
                )
                let localComment = HomeOrderComment.makeLocalAttachmentComment(
                    id: localCommentID,
                    orderID: orderID,
                    attachment: localAttachment,
                    user: currentUser,
                    deliveryState: .pending
                )
                pendingCommentPayloads[localCommentID] = .attachment(attachment, localFileURL)
                mergeComment(localComment)
                requestCommentScrollToBottom()
                await finishSendingComment(localCommentID: localCommentID, payload: .attachment(attachment, localFileURL))
            } catch {
                attachmentErrorMessage = resolveActionError(error)
            }
        }
    }

    private func finishSendingComment(localCommentID: Int, payload: PendingOrderCommentPayload) async {
        do {
            let createdComment: HomeOrderComment
            switch payload {
            case let .text(text):
                let mentionedUserIDs = MentionEngine.mentionedUserIDs(in: text, participants: store.participants)
                createdComment = try await store.addOrderComment(accessToken: session.currentAccessToken, orderID: orderID, text: text, mentionedUserIDs: mentionedUserIDs)
            case let .attachment(attachment, _):
                let uploadedAttachment = try await store.uploadOrderCommentAttachment(
                    accessToken: session.currentAccessToken,
                    data: attachment.data,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    attachmentKind: attachment.attachmentKind
                )
                createdComment = try await store.addOrderComment(
                    accessToken: session.currentAccessToken,
                    orderID: orderID,
                    text: nil,
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
            }
            replaceComment(localID: localCommentID, with: createdComment)
        } catch {
            updateCommentState(commentID: localCommentID, deliveryState: .failed)
            errorMessage = resolveActionError(error)
        }
    }

    private func retryFailedComment(_ comment: HomeOrderComment) {
        guard let payload = pendingCommentPayloads[comment.id] else { return }
        updateCommentState(commentID: comment.id, deliveryState: .pending)
        requestCommentScrollToBottom()
        Task {
            await finishSendingComment(localCommentID: comment.id, payload: payload)
        }
    }

    private func deleteComment(_ comment: HomeOrderComment) {
        if commentReplyTarget?.id == comment.id {
            commentReplyTarget = nil
        }
        if commentEditTarget?.id == comment.id {
            cancelCommentEdit()
        }

        // Неотправленные (локальные) сообщения просто убираем — на сервере их ещё нет.
        if comment.isLocalOnly {
            comments.removeAll { $0.id == comment.id }
            pendingCommentPayloads.removeValue(forKey: comment.id)
            return
        }

        // Отправленные удаляем на сервере (для всех), как в основном чате. Оптимистично
        // убираем из списка, при ошибке возвращаем обратно.
        comments.removeAll { $0.id == comment.id }
        Task {
            do {
                try await store.deleteOrderComment(accessToken: session.currentAccessToken, orderID: orderID, commentID: comment.id)
            } catch {
                mergeComment(comment)
                errorMessage = resolveActionError(error)
            }
        }
    }

    private func openAttachment(_ attachment: HomeOrderCommentAttachment) {
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
                let localURL = try await store.downloadOrderCommentAttachmentToTemporaryURL(attachment)
                localFilePreview = LocalAttachmentPreview(url: localURL)
            } catch {
                attachmentErrorMessage = resolveActionError(error)
            }
        }
    }

    private func makeOrderItemRequest(
        item: HomeOrderItem,
        statusID: Int?,
        sourceEstablishmentID: Int?,
        destinationEstablishmentID: Int?,
        checkpointStarted: Bool,
        checkpointCompleted: Bool
    ) -> HomeOrderItemCreateRequest {
        HomeOrderItemCreateRequest(
            productID: item.orderItemProductID,
            productArticle: item.orderItemArticle,
            productName: item.orderItemName,
            orderItemQuantity: item.orderItemQuantity,
            orderItemPrice: item.orderItemPrice,
            orderItemStatusID: statusID,
            orderItemNote: item.orderItemNote,
            orderItemSourceEstablishmentID: sourceEstablishmentID,
            orderItemDestinationEstablishmentID: destinationEstablishmentID,
            orderItemCurrencyID: item.orderItemCurrencyID,
            orderItemCheckpointStarted: checkpointStarted,
            orderItemCheckpointCompleted: checkpointCompleted
        )
    }

    private func shouldResetChecklistState(for statusID: Int?) -> Bool {
        guard let statusID else { return false }
        guard let status = orderItemStatuses.first(where: { $0.id == statusID }) else { return false }
        return ["Заказ поставщику", "Перемещение"].contains(status.statusStatus)
    }

    private func isCdekOrder(_ order: HomeOrder) -> Bool {
        order.orderMethodName == "СДЭК" || order.orderSubMethod == "СДЭК"
    }

    @ViewBuilder
    private func cdekBlock(order: HomeOrder) -> some View {
        let c = cdekOverride ?? order.cdek
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("СДЭК").font(.system(size: 17, weight: .semibold, design: .rounded))
                if let c, c.hasWaybill, let track = c.trackNumber, !track.isEmpty {
                    Button { copyTrack(track) } label: {
                        Image(systemName: didCopyTrack ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(didCopyTrack ? Color.green : Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background((didCopyTrack ? Color.green : Color.accentColor).opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Копировать трек-номер")
                }
                Spacer()
            }
            if let c, c.hasWaybill {
                // Трек + иконка «Пересоздать» в одну строку. Пересоздание сбрасывает
                // накладную (спасает от «Некорректный заказ») и открывает форму заново.
                HStack(spacing: 8) {
                    if let track = c.trackNumber, !track.isEmpty {
                        Text("Трек-номер: \(track)").font(.subheadline)
                    } else {
                        Text("Трек-номер: создаётся…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button { cdekRecreateConfirm = true } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(cdekRecreating ? Color.secondary : Color.orange)
                            .frame(width: 28, height: 28)
                            .background((cdekRecreating ? Color.secondary : Color.orange).opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(cdekRecreating)
                    .accessibilityLabel("Пересоздать накладную")
                    Spacer()
                }
                if let st = c.status, !st.isEmpty {
                    Text("Статус: \(st)").font(.subheadline).foregroundStyle(.secondary)
                }
                // Статус обновляется автоматически (вебхук СДЭК + при открытии карточки).
            } else {
                Button { cdekSheetOrder = order } label: {
                    Label("Создать накладную", systemImage: "shippingbox").font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func afterCdekWaybillCreated(_ c: HomeOrderCdek) {
        cdekOverride = c
        // Печать асинхронна: ~несколько секунд ждём трек И подтягиваем комментарии
        // (накладные-PDF от cdek_helper) в открытую карточку, не дожидаясь переоткрытия.
        Task {
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let oid = order?.id,
                   let upd = try? await store.cdekWaybillStatus(accessToken: session.currentAccessToken, orderID: oid) {
                    cdekOverride = upd
                }
                await loadOrder()
            }
        }
    }

    private func recreateCdek(order: HomeOrder) {
        guard !cdekRecreating else { return }
        cdekRecreating = true
        Task {
            defer { cdekRecreating = false }
            if let upd = try? await store.deleteCdekWaybill(accessToken: session.currentAccessToken, orderID: order.id) {
                cdekOverride = upd
                await loadOrder()
                // Открываем форму пересоздания с сохранёнными данными.
                cdekSheetOrder = cachedOrderForSheet(order)
            }
        }
    }

    private func cachedOrderForSheet(_ fallback: HomeOrder) -> HomeOrder {
        order ?? fallback
    }

    private func copyTrack(_ track: String) {
        UIPasteboard.general.string = track
        didCopyTrack = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run { didCopyTrack = false }
        }
    }

    private func infoRows(for order: HomeOrder) -> [BusinessDocumentInfoRowModel] {
        var rows = [
            BusinessDocumentInfoRowModel(title: "Точка", value: order.orderEstablishmentName ?? establishmentTitle(for: order.orderEstablishmentID)),
            BusinessDocumentInfoRowModel(title: "Клиент", value: order.orderCustomer),
            BusinessDocumentInfoRowModel(title: "Комментарий", value: normalizedValue(order.orderInfo)),
            BusinessDocumentInfoRowModel(title: "Метод", value: methodTitle(for: order))
        ]
        if let salesChannel = order.orderSalesChannel, !salesChannel.isEmpty {
            rows.append(BusinessDocumentInfoRowModel(title: "Канал", value: salesChannel))
        }
        if let contactMethod = order.orderContactMethod, !contactMethod.isEmpty {
            rows.append(BusinessDocumentInfoRowModel(title: "Способ связи", value: contactMethod))
        }
        rows.append(BusinessDocumentInfoRowModel(title: "Оплата", value: paymentValue(for: order)))
        rows.append(BusinessDocumentInfoRowModel(title: "Создана", value: formattedDate(order.orderCreatedAt)))
        if let owner = order.orderOwnerDisplayName {
            rows.append(BusinessDocumentInfoRowModel(title: "Кем создана", value: owner))
        }
        return rows
    }

    /// Строка «Оплата» в параметрах: когда и кто отметил (кнопка — в карточке СРМ).
    private func paymentValue(for order: HomeOrder) -> String {
        guard order.isPaid else { return "Не оплачено" }
        var parts = ["Оплачено"]
        if let paidAt = order.orderPaidAt, !paidAt.isEmpty {
            parts.append(formattedDate(paidAt))
        }
        if let paidBy = order.orderPaidByDisplayName {
            parts.append(paidBy)
        }
        return parts.joined(separator: " · ")
    }

    private func methodTitle(for order: HomeOrder) -> String {
        // Способ может быть не выбран (заказ с сайта) — показываем прочерк, как у
        // любого незаполненного параметра, а не подставляем что-то своё.
        guard order.orderMethodID != nil || order.orderMethodName != nil else { return "-" }
        let baseTitle = order.orderMethodName ?? store.referenceData.orderMethods.first(where: { $0.id == order.orderMethodID })?.orderMethodName ?? "Метод"
        guard let orderSubMethod = order.orderSubMethod, !orderSubMethod.isEmpty else {
            return baseTitle
        }
        return "\(baseTitle) / \(orderSubMethod)"
    }

    private func establishmentTitle(for id: Int) -> String {
        store.referenceData.establishments.first(where: { $0.id == id })?.establishmentName ?? "Точка"
    }

    private func currencyTitle(for currencyID: Int?) -> String {
        guard let currency = store.referenceData.currencies.first(where: { $0.id == currencyID }) else {
            return "USD"
        }
        if let currencySign = currency.currencySign, !currencySign.isEmpty {
            return currencySign
        }
        return currency.currencyName
    }

    private func orderItemStatusTitle(for item: HomeOrderItem) -> String {
        if let title = item.orderItemStatus, !title.isEmpty {
            return title
        }
        return "Статус"
    }

    private func orderItemStatusColor(for item: HomeOrderItem) -> Color {
        BusinessDocumentColors.statusColor(item.orderItemStatusColor)
    }

    private func normalizedValue(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func formattedDate(_ rawValue: String?) -> String {
        guard let date = HomeMessageDateParser.parse(rawValue) else {
            return rawValue ?? "-"
        }
        return BusinessDocumentFormatters.dateTime.string(from: date)
    }
}

private struct OrderDocumentItemsSection: View {
    let title: String
    let items: [OrderDocumentItemViewModel]
    let isSaving: Bool
    let onSelectStatus: (Int, Int) -> Void

    @State private var didCopy = false

    // Итоги, сгруппированные по валюте (в заказе позиции могут быть в разных валютах),
    // в порядке первого появления валюты в списке.
    private var totalsByCurrency: [(currency: String, total: Double)] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for item in items {
            guard let lineTotal = item.lineTotal else { continue }
            if totals[item.currencyTitle] == nil { order.append(item.currencyTitle) }
            totals[item.currencyTitle, default: 0] += lineTotal
        }
        return order.compactMap { currency in
            totals[currency].map { (currency, $0) }
        }
    }

    private var totalSummaryText: String {
        totalsByCurrency
            .map { "\(AppAmount.grouped(formatOrderAmount($0.total))) \($0.currency)" }
            .joined(separator: " + ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                if !items.isEmpty {
                    Menu {
                        Button("Скопировать номенклатуру") { copyItems(withPrice: false) }
                        Button("Скопировать с кол-вом и ценой") { copyItems(withPrice: true) }
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(didCopy ? Color.green : Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background((didCopy ? Color.green : Color.accentColor).opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Копировать позиции")
                }

                Spacer()
            }

            if items.isEmpty {
                Text("Позиции отсутствуют")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 10) {
                            OrderItemStatusMenu(
                                title: item.statusTitle,
                                color: item.statusColor,
                                statuses: item.statuses,
                                selectedStatusID: item.selectedStatusID,
                                isDisabled: isSaving,
                                onSelect: { statusID in
                                    onSelectStatus(item.id, statusID)
                                }
                            )

                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            OrderCompactMetricView(title: "Кол-во", value: item.quantity)
                            OrderCompactMetricView(title: "Цена", value: AppAmount.grouped(item.price))
                            OrderCompactMetricView(title: "Валюта", value: item.currencyTitle)
                            OrderCompactMetricView(
                                title: "Сумма",
                                value: item.lineTotal.map { "\(AppAmount.grouped(formatOrderAmount($0))) \(item.currencyTitle)" } ?? "—"
                            )
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                    )
                }

                if !totalsByCurrency.isEmpty {
                    Divider()
                        .padding(.vertical, 2)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Spacer()
                        Text("Итого")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(totalSummaryText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func copyItems(withPrice: Bool) {
        var lines = items.map { item -> String in
            if withPrice {
                let priceText = item.priceValue.map { formatOrderAmount($0) } ?? item.price
                return "\(item.quantityValue) шт. *  \(item.name) *  \(priceText) \(item.currencyTitle)"
            }
            return "\(item.quantityValue) шт. *  \(item.name)"
        }
        if withPrice && !totalsByCurrency.isEmpty {
            lines.append("")
            lines.append("Итого: \(totalSummaryText)")
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")

        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run { didCopy = false }
        }
    }
}

private struct OrderCompactMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OrderCommentsSection: View {
    let comments: [HomeOrderComment]
    let currentUserID: Int?
    var currentUserIsAdmin: Bool = false
    var mentionNames: [String] = []
    let isComposerActive: Bool
    let onOpenAttachment: (HomeOrderCommentAttachment) -> Void
    let onRetryComment: (HomeOrderComment) -> Void
    let onReplyComment: (HomeOrderComment) -> Void
    let onEditComment: (HomeOrderComment) -> Void
    let onCopyComment: (HomeOrderComment) -> Void
    let onDeleteComment: (HomeOrderComment) -> Void
    let onBackgroundTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Чат заказа")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            Group {
                if comments.isEmpty {
                    Text("Пока без сообщений")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBackgroundTap)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(comments) { comment in
                                    OrderCommentRow(
                                        comment: comment,
                                        isOwn: comment.ownerUserID == currentUserID,
                                        canEdit: comment.ownerUserID == currentUserID,
                                        canDelete: comment.ownerUserID == currentUserID || currentUserIsAdmin,
                                        mentionNames: mentionNames,
                                        onOpenAttachment: onOpenAttachment,
                                        onRetryComment: onRetryComment,
                                        onReplyComment: onReplyComment,
                                        onEditComment: onEditComment,
                                        onCopyComment: onCopyComment,
                                        onDeleteComment: onDeleteComment
                                    )
                                    .id(comment.id)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .frame(maxHeight: isComposerActive ? 380 : 310)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBackgroundTap)
                        .onAppear {
                            if let lastID = comments.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                        .onChange(of: comments.last?.id) { _, newID in
                            guard let newID else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(newID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct OrderCommentRow: View {
    let comment: HomeOrderComment
    let isOwn: Bool
    var canEdit: Bool = false
    var canDelete: Bool = false
    var mentionNames: [String] = []
    let onOpenAttachment: (HomeOrderCommentAttachment) -> Void
    let onRetryComment: (HomeOrderComment) -> Void
    let onReplyComment: (HomeOrderComment) -> Void
    let onEditComment: (HomeOrderComment) -> Void
    let onCopyComment: (HomeOrderComment) -> Void
    let onDeleteComment: (HomeOrderComment) -> Void

    // Редактировать можно только своё текстовое сообщение без вложений (как в чате).
    private var isEditable: Bool {
        canEdit && !comment.isLocalOnly && comment.attachments.isEmpty && comment.hasCopyableText
    }

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
            Text(comment.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)

            VStack(alignment: .leading, spacing: 6) {
                if let reply = comment.replyFragment {
                    replyPreview(reply)
                }

                if !comment.visibleText.isEmpty {
                    Text(MentionEngine.attributedText(for: comment.visibleText, mentionNames: mentionNames, color: MentionEngine.mentionHighlightColor))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !comment.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(comment.attachments) { attachment in
                            OrderCommentAttachmentCard(attachment: attachment, isOwn: isOwn, onOpen: {
                                onOpenAttachment(attachment)
                            })
                        }
                    }
                }

                deliveryMeta
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isOwn ? Color(red: 0.96, green: 0.44, blue: 0.27) : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .frame(maxWidth: 320, alignment: isOwn ? .trailing : .leading)
            .contextMenu {
                if !comment.isLocalOnly {
                    Button {
                        onReplyComment(comment)
                    } label: {
                        Label("Ответить", systemImage: "arrowshape.turn.up.left")
                    }
                }

                if isEditable {
                    Button {
                        onEditComment(comment)
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                }

                if comment.canRetryDelivery {
                    Button {
                        onRetryComment(comment)
                    } label: {
                        Label("Отправить снова", systemImage: "arrow.clockwise")
                    }
                }

                if comment.hasCopyableText {
                    Button {
                        onCopyComment(comment)
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                }

                if canDelete || comment.isLocalOnly {
                    Button(role: .destructive) {
                        onDeleteComment(comment)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    @ViewBuilder
    private func replyPreview(_ reply: HomeReplyFragment) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill((isOwn ? Color.white : Color.accentColor).opacity(isOwn ? 0.9 : 0.8))
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(reply.author)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOwn ? Color.white : Color.primary)
                    .lineLimit(1)

                if !reply.message.isEmpty {
                    Text(reply.message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle((isOwn ? Color.white : Color.secondary).opacity(0.82))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            (isOwn ? Color.white.opacity(0.16) : Color.primary.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deliveryMeta: some View {
        HStack(spacing: 6) {
            switch comment.deliveryState {
            case .pending:
                ProgressView()
                    .controlSize(.mini)
                    .tint((isOwn ? Color.white : Color.secondary).opacity(0.72))
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.92))
            case .sent:
                EmptyView()
            }

            if let createdAt = comment.parsedCreatedAt {
                Text(Self.timeFormatter.string(from: createdAt))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle((isOwn ? Color.white : Color.secondary).opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct OrderCommentAttachmentCard: View {
    let attachment: HomeOrderCommentAttachment
    let isOwn: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isOwn ? 0.16 : 0.10))
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if attachment.isPhoto, let mediaURL = attachment.mediaURL {
                        AsyncImage(url: mediaURL) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle((isOwn ? Color.white : Color.primary).opacity(0.82))
                            default:
                                ProgressView()
                                    .tint(isOwn ? .white : .primary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .clipped()
                    } else {
                        Image(systemName: attachment.isPhoto ? "photo" : "doc")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle((isOwn ? Color.white : Color.primary).opacity(0.82))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.attachmentOriginalFilename)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOwn ? Color.white : Color.primary)
                    .lineLimit(2)

                if let size = attachment.attachmentSizeBytes {
                    Text(Self.byteFormatter.string(fromByteCount: Int64(size)))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle((isOwn ? Color.white : Color.secondary).opacity(0.72))
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct OrderCommentPhotoViewer: View {
    let attachment: HomeOrderCommentAttachment
    let onDismiss: () -> Void

    var body: some View {
        PhotoAttachmentViewer(mediaURL: attachment.mediaURL, onDismiss: onDismiss)
    }
}

private struct OrderCommentComposeBanner: View {
    let title: String
    var author: String?
    let snippet: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.9))
                .frame(width: 3, height: 30)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                if let author {
                    Text(author)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(snippet)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OrderCommentInputPanel: View {
    @Binding var text: String
    let isTextFieldFocused: FocusState<Bool>.Binding?
    let isSending: Bool
    let onAttach: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: onAttach) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: $text,
                prompt: Text("Сообщение").foregroundStyle(.secondary),
                axis: .vertical
            )
            .orderCommentFocused(isTextFieldFocused)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1 ... 4)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onSend) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private extension View {
    @ViewBuilder
    func orderCommentFocused(_ binding: FocusState<Bool>.Binding?) -> some View {
        if let binding {
            self.focused(binding)
        } else {
            self
        }
    }
}

private struct OrderCommentAttachmentMenu: View {
    let onPhotoTap: () -> Void
    let onCameraTap: () -> Void
    let onFileTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Файл или фото")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 12)

            OrderCommentAttachmentMenuButton(title: "Фото", action: onPhotoTap)
            OrderCommentAttachmentMenuButton(title: "Камера", action: onCameraTap)
            OrderCommentAttachmentMenuButton(title: "Файл", action: onFileTap)
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
}

private struct OrderCommentAttachmentMenuButton: View {
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

private struct OrderDocumentItemViewModel: Identifiable {
    let id: Int
    let name: String
    let statusTitle: String
    let statusColor: Color
    let selectedStatusID: Int?
    let statuses: [HomeStatus]
    let quantity: String
    let price: String
    let currencyTitle: String
    let quantityValue: Int
    let priceValue: Double?

    /// Сумма по позиции (цена × количество), если цена распарсилась.
    var lineTotal: Double? {
        priceValue.map { $0 * Double(quantityValue) }
    }
}

/// Парсит строковую цену бэкенда (возможны пробелы-разделители и запятая) в Double.
private func parseOrderItemPrice(_ raw: String) -> Double? {
    let normalized = raw
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ",", with: ".")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : Double(normalized)
}

/// Форматирует сумму: целые — без дробной части, иначе две цифры.
private func formatOrderAmount(_ value: Double) -> String {
    if value.rounded() == value {
        return String(format: "%.0f", value)
    }
    return String(format: "%.2f", value)
}

private struct OrderItemMovementSelection: Identifiable {
    let itemID: Int
    let statusID: Int
    let sourceEstablishmentID: Int?
    let destinationEstablishmentID: Int?

    var id: String {
        "\(itemID)-\(statusID)"
    }
}

private struct OrderItemStatusMenu: View {
    let title: String
    let color: Color
    let statuses: [HomeStatus]
    let selectedStatusID: Int?
    let isDisabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(statuses) { status in
                Button {
                    onSelect(status.id)
                } label: {
                    Text(status.statusStatus)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke((selectedStatusID == nil ? Color.clear : color).opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || statuses.isEmpty)
    }
}

private struct OrderItemMovementRouteSheet: View {
    let establishments: [HomeEstablishment]
    let initialSourceEstablishmentID: Int?
    let initialDestinationEstablishmentID: Int?
    let onClose: () -> Void
    let onConfirm: (Int, Int) -> Void

    @State private var sourceEstablishmentID: Int?
    @State private var destinationEstablishmentID: Int?

    init(
        establishments: [HomeEstablishment],
        initialSourceEstablishmentID: Int?,
        initialDestinationEstablishmentID: Int?,
        onClose: @escaping () -> Void,
        onConfirm: @escaping (Int, Int) -> Void
    ) {
        self.establishments = establishments
        self.initialSourceEstablishmentID = initialSourceEstablishmentID
        self.initialDestinationEstablishmentID = initialDestinationEstablishmentID
        self.onClose = onClose
        self.onConfirm = onConfirm
        _sourceEstablishmentID = State(initialValue: initialSourceEstablishmentID)
        _destinationEstablishmentID = State(initialValue: initialDestinationEstablishmentID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Перемещение")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Выбери точки Откуда и Куда")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            routeSelector(title: "Откуда", selection: $sourceEstablishmentID)
            routeSelector(title: "Куда", selection: $destinationEstablishmentID)

            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    guard let sourceEstablishmentID, let destinationEstablishmentID else { return }
                    onConfirm(sourceEstablishmentID, destinationEstablishmentID)
                } label: {
                    Text("Сохранить")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sourceEstablishmentID == nil || destinationEstablishmentID == nil || sourceEstablishmentID == destinationEstablishmentID)
                .opacity(sourceEstablishmentID == nil || destinationEstablishmentID == nil || sourceEstablishmentID == destinationEstablishmentID ? 0.55 : 1)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func routeSelector(title: String, selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Menu {
                ForEach(establishments) { establishment in
                    Button {
                        selection.wrappedValue = establishment.id
                    } label: {
                        Text(establishment.establishmentName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(establishmentTitle(for: selection.wrappedValue) ?? "Выбери точку")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func establishmentTitle(for id: Int?) -> String? {
        establishments.first(where: { $0.id == id })?.establishmentName
    }
}
