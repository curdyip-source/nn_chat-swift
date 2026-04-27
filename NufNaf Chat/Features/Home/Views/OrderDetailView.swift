import SwiftUI

struct OrderDetailView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var store: HomeStore
    @FocusState private var isCommentFieldFocused: Bool

    let orderID: Int
    let onClose: () -> Void

    @State private var order: HomeOrder?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isEditSheetPresented = false
    @State private var comments: [HomeOrderComment] = []
    @State private var commentDraft = ""
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
    @State private var commentScrollRequest = 0

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

            if let order, isEditSheetPresented {
                orderEditOverlay(order: order)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isEditSheetPresented)
        .animation(.easeInOut(duration: 0.18), value: isCommentAttachmentMenuPresented)
        .task(id: orderID) {
            await loadOrder()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if order != nil {
                commentComposerDock
            }
        }
        .onChange(of: isEditSheetPresented) { _, isPresented in
            if isPresented {
                closeCommentAttachmentMenu()
                dismissCommentKeyboard()
            }
        }
        .onChange(of: isCommentFieldFocused) { _, isFocused in
            guard isFocused else { return }
            commentScrollRequest += 1
        }
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
            onClose: onClose,
            headerActionSystemImage: order == nil ? nil : "pencil",
            onHeaderAction: order == nil ? nil : { isEditSheetPresented = true },
            scrollTargetID: "order-comments-section",
            scrollRequest: commentScrollRequest,
            contentHorizontalPadding: 0,
            headerContent: {
                if let order {
                    BusinessDocumentStatusButtons(
                        statuses: orderStatuses,
                        selectedStatusID: order.orderStatusID,
                        isSaving: isSaving,
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
                                    currencyTitle: currencyTitle(for: $0.orderItemCurrencyID)
                                )
                            },
                            isSaving: isSaving,
                            onSelectStatus: handleItemStatusSelection
                        )

                        OrderCommentsSection(
                            comments: comments,
                            currentUserID: session.currentUser?.userID,
                            isComposerActive: isCommentFieldFocused || isCommentAttachmentMenuPresented,
                            onOpenAttachment: openAttachment,
                            onRetryComment: retryFailedComment,
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

    private var orderStatuses: [HomeStatus] {
        store.referenceData.statuses.filter { $0.statusType == "orders" }
    }

    private var orderItemStatuses: [HomeStatus] {
        store.referenceData.statuses.filter { $0.statusType == "order_products" }
    }

    private var sortedOrderComments: [HomeOrderComment] {
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

    private func editingItemStatusIDs(for order: HomeOrder) -> [Int: Int?] {
        Dictionary(uniqueKeysWithValues: order.items.map { ($0.id, $0.orderItemStatusID) })
    }

    private func orderEditOverlay(order: HomeOrder) -> some View {
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

    private func loadOrder() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedOrder = try await store.fetchOrder(accessToken: session.currentAccessToken, orderID: orderID)
            order = loadedOrder
            comments = sortComments(loadedOrder.comments)
            markCommentsRead(loadedOrder.comments)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateStatus(_ statusID: Int) {
        guard let order else { return }
        guard order.orderStatusID != statusID else { return }

        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                let updatedOrder = try await store.updateOrderStatus(accessToken: session.currentAccessToken, order: order, statusID: statusID)
                self.order = updatedOrder
                self.comments = sortComments(updatedOrder.comments)
                markCommentsRead(updatedOrder.comments)
            } catch {
                errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sendComment() async {
        let trimmedText = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let localCommentID = nextLocalCommentID()
        let localComment = HomeOrderComment.makeLocalTextComment(
            id: localCommentID,
            orderID: orderID,
            text: trimmedText,
            user: currentUser,
            deliveryState: .pending
        )
        pendingCommentPayloads[localCommentID] = .text(trimmedText)
        mergeComment(localComment)
        requestCommentScrollToBottom()
        commentDraft = ""
        errorMessage = nil
        isSendingComment = false

        await finishSendingComment(localCommentID: localCommentID, payload: .text(trimmedText))
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
            userCreatedAt: nil
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
                attachmentErrorMessage = error.localizedDescription
            }
        }
    }

    private func finishSendingComment(localCommentID: Int, payload: PendingOrderCommentPayload) async {
        do {
            let createdComment: HomeOrderComment
            switch payload {
            case let .text(text):
                createdComment = try await store.addOrderComment(accessToken: session.currentAccessToken, orderID: orderID, text: text)
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
            errorMessage = error.localizedDescription
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
        guard comment.isLocalOnly else { return }
        comments.removeAll { $0.id == comment.id }
        pendingCommentPayloads.removeValue(forKey: comment.id)
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
                attachmentErrorMessage = error.localizedDescription
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
            productArticle: item.orderItemProductID == nil ? item.orderItemArticle : nil,
            productName: item.orderItemProductID == nil ? item.orderItemName : nil,
            orderItemQuantity: item.orderItemQuantity,
            orderItemPrice: item.orderItemPrice,
            orderItemStatusID: statusID,
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
        return ["Заказ", "Перемещение"].contains(status.statusStatus)
    }

    private func infoRows(for order: HomeOrder) -> [BusinessDocumentInfoRowModel] {
        [
            BusinessDocumentInfoRowModel(title: "Точка", value: order.orderEstablishmentName ?? establishmentTitle(for: order.orderEstablishmentID)),
            BusinessDocumentInfoRowModel(title: "Клиент", value: order.orderCustomer),
            BusinessDocumentInfoRowModel(title: "Комментарий", value: normalizedValue(order.orderInfo)),
            BusinessDocumentInfoRowModel(title: "Метод", value: methodTitle(for: order)),
            BusinessDocumentInfoRowModel(title: "Создана", value: formattedDate(order.orderCreatedAt))
        ]
    }

    private func methodTitle(for order: HomeOrder) -> String {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))

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
                            OrderCompactMetricView(title: "Цена", value: item.price)
                            OrderCompactMetricView(title: "Валюта", value: item.currencyTitle)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .padding(.trailing, 18)
        .padding(.leading, 8)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
    let isComposerActive: Bool
    let onOpenAttachment: (HomeOrderCommentAttachment) -> Void
    let onRetryComment: (HomeOrderComment) -> Void
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
                                        onOpenAttachment: onOpenAttachment,
                                        onRetryComment: onRetryComment,
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
    let onOpenAttachment: (HomeOrderCommentAttachment) -> Void
    let onRetryComment: (HomeOrderComment) -> Void
    let onDeleteComment: (HomeOrderComment) -> Void

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
            Text(comment.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)

            VStack(alignment: .leading, spacing: 6) {
                if !comment.visibleText.isEmpty {
                    Text(comment.visibleText)
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
                if comment.canRetryDelivery {
                    Button("Отправить снова") {
                        onRetryComment(comment)
                    }

                    Button("Удалить", role: .destructive) {
                        onDeleteComment(comment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
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
        PhotoAttachmentViewer(attachment: attachment.asMessageAttachment, onDismiss: onDismiss)
    }
}

private extension HomeOrderCommentAttachment {
    var asMessageAttachment: HomeMessageAttachment {
        HomeMessageAttachment(
            attachmentID: attachmentID,
            attachmentKind: attachmentKind,
            attachmentOriginalFilename: attachmentOriginalFilename,
            attachmentMimeType: attachmentMimeType,
            attachmentStorageKey: attachmentStorageKey,
            attachmentSizeBytes: attachmentSizeBytes,
            attachmentCreatedAt: attachmentCreatedAt,
            attachmentLocalFilePath: attachmentLocalFilePath
        )
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
