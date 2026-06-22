import SwiftUI

struct CRMDocumentsListView: View {
    @EnvironmentObject private var session: AppSession

    let messages: [HomeMessage]
    let referenceData: HomeReferenceDataResponse
    let isLoading: Bool
    let errorMessage: String?
    let updatingDocumentKey: String?
    @Binding var selectedSection: CRMSection
    let onOpenDocument: (String, Int) -> Void
    let onSelectOrderStatus: (HomeOrder, Int) -> Void
    let onSelectOrderItemStatus: (HomeOrder, Int, Int, Int?, Int?, String?) -> Void
    let onCollectShipmentItem: (HomeOrder, Int) -> Void
    let onCompleteShipmentOrder: (HomeOrder) -> Void
    let onUpdateOrderItemNote: (HomeOrder, Int, String?) -> Void
    let onSearchSupplierContacts: (String) async -> [HomeContact]
    let onSelectInventoryStatus: (HomeInventory, Int) -> Void
    let onSelectProductRegistrationStatus: (HomeProductRegistration, Int) -> Void

    @State private var movementSelection: CRMMovementSelection?
    @State private var supplierSelection: CRMSupplierSelection?
    @State private var shipmentCompletionConfirmation: CRMShipmentOrderCompletionConfirmation?
    @State private var supplierQuery = ""
    @State private var supplierResults: [HomeContact] = []
    @State private var isSearchingSuppliers = false

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                crmSearchField
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.red.opacity(0.92))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        if isLoading && messages.isEmpty {
                            Text("Загружаем CRM...")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if currentSectionIsEmpty {
                            Text(emptyStateTitle)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        } else {
                            if selectedSection == .products {
                                ForEach(productEntries) { entry in
                                    CRMOrderProductRow(
                                        entry: entry,
                                        itemStatuses: orderItemStatuses,
                                        currencyTitleProvider: currencyTitle(for:),
                                        isSaving: updatingDocumentKey == documentKey(kind: "order", id: entry.order.id),
                                        onOpen: {
                                            onOpenDocument("order", entry.order.id)
                                        },
                                        onSelectStatus: { statusID in
                                            handleOrderItemStatusSelection(order: entry.order, itemID: entry.item.id, statusID: statusID, promptForSupplier: true)
                                        },
                                        onUpdateNote: { note in
                                            onUpdateOrderItemNote(entry.order, entry.item.id, note)
                                        }
                                    )
                                    .environment(\.colorScheme, .light)
                                }
                            } else {
                                ForEach(displayedOrders) { order in
                                    CRMOrderCardView(
                                        order: order,
                                        isShipmentMode: selectedSection == .shipments,
                                        orderMethods: referenceData.orderMethods,
                                        itemStatuses: orderItemStatuses,
                                        statuses: referenceData.statuses.filter { $0.statusType == "orders" },
                                        currencyTitleProvider: currencyTitle(for:),
                                        isSaving: updatingDocumentKey == documentKey(kind: "order", id: order.id),
                                        onOpen: {
                                            onOpenDocument("order", order.id)
                                        },
                                        onSelectStatus: { statusID in
                                            onSelectOrderStatus(order, statusID)
                                        },
                                        onSelectItemStatus: { itemID, statusID in
                                            handleOrderItemStatusSelection(order: order, itemID: itemID, statusID: statusID)
                                        },
                                        onCollectShipmentItem: { itemID in
                                            onCollectShipmentItem(order, itemID)
                                        },
                                        onCompleteShipmentOrder: {
                                            shipmentCompletionConfirmation = CRMShipmentOrderCompletionConfirmation(order: order)
                                        }
                                    )
                                    .environment(\.colorScheme, .light)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .padding(.top, 8)
                    // Резерв снизу под закреплённое меню разделов (оно — оверлей, не в потоке).
                    .padding(.bottom, 96)
                }
                // Небольшой запас снизу, чтобы поле «Заметка» поднималось чуть выше
                // клавиатуры, а не упиралось в неё.
                .contentMargins(.bottom, 16, for: .scrollContent)
            }

            if let movementSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.movementSelection = nil
                    }

                CRMMovementRouteSheet(
                    establishments: referenceData.establishments,
                    initialSourceEstablishmentID: movementSelection.sourceEstablishmentID,
                    initialDestinationEstablishmentID: movementSelection.destinationEstablishmentID,
                    onClose: {
                        self.movementSelection = nil
                    },
                    onConfirm: { sourceID, destinationID in
                        onSelectOrderItemStatus(
                            movementSelection.order,
                            movementSelection.itemID,
                            movementSelection.statusID,
                            sourceID,
                            destinationID,
                            nil
                        )
                        self.movementSelection = nil
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if let supplierSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissSupplierSelection()
                    }

                CRMSupplierSelectionSheet(
                    query: $supplierQuery,
                    results: supplierResults,
                    isSearching: isSearchingSuppliers,
                    onQueryChange: handleSupplierQueryChange,
                    onClose: {
                        dismissSupplierSelection()
                    },
                    onClear: {
                        clearSupplierQuery()
                    },
                    onSelectContact: { contact in
                        applySupplierContact(contact)
                    },
                    onCreateContact: {
                        let normalizedSupplier = supplierQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !normalizedSupplier.isEmpty else { return }
                        onSelectOrderItemStatus(
                            supplierSelection.order,
                            supplierSelection.itemID,
                            supplierSelection.statusID,
                            nil,
                            nil,
                            normalizedSupplier
                        )
                        dismissSupplierSelection()
                    },
                    onConfirm: {
                        let normalizedSupplier = supplierQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSelectOrderItemStatus(
                            supplierSelection.order,
                            supplierSelection.itemID,
                            supplierSelection.statusID,
                            nil,
                            nil,
                            normalizedSupplier.isEmpty ? nil : normalizedSupplier
                        )
                        dismissSupplierSelection()
                    },
                    onSkip: {
                        onSelectOrderItemStatus(
                            supplierSelection.order,
                            supplierSelection.itemID,
                            supplierSelection.statusID,
                            nil,
                            nil,
                            nil
                        )
                        dismissSupplierSelection()
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Меню закреплено внизу. Клавиатура сдвигает весь CRM-блок вверх; компенсируем
            // сдвиг меню ровно на текущую вставку клавиатуры (geo.safeAreaInsets.bottom).
            // Это та же системная величина, что двигает блок, в той же анимации —
            // поэтому без рассинхрона и без «всплывания».
            GeometryReader { geo in
                CRMSectionBar(selection: $selectedSection)
                    .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, max(AppTheme.PageLayout.bottomPadding - 8, 8) + 15)
                    .background(AppTheme.background.opacity(0.96))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: geo.safeAreaInsets.bottom)
            }
        }
        .alert(item: $shipmentCompletionConfirmation) { confirmation in
            Alert(
                title: Text("Подтвердите выполнение"),
                message: Text("Отметить заказ как выполненный?"),
                primaryButton: .default(Text("Подтвердить"), action: {
                    onCompleteShipmentOrder(confirmation.order)
                    shipmentCompletionConfirmation = nil
                }),
                secondaryButton: .cancel(Text("Отмена"), action: {
                    shipmentCompletionConfirmation = nil
                })
            )
        }
    }

    private var crmSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))

            TextField(
                "",
                text: $session.crmSearchQuery,
                prompt: Text("Товар, заказ, точка, клиент")
                    .foregroundStyle(Color.white.opacity(0.82))
            )
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white)
                .submitLabel(.search)

            if !session.crmSearchQuery.isEmpty {
                Button {
                    session.crmSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        )
    }

    private var displayedOrders: [HomeOrder] {
        switch selectedSection {
        case .orders:
            return orderMessages.compactMap(\.order)
        case .shipments:
            return orderMessages.compactMap(\.order).filter(isShipmentOrder)
        case .products:
            return []
        }
    }

    private var orderMessages: [HomeMessage] {
        messages.filter { $0.order != nil }
    }

    private var productEntries: [CRMOrderProductEntry] {
        orderMessages.compactMap(\.order)
            .flatMap { order in
                order.items.map { item in
                    CRMOrderProductEntry(order: order, item: item)
                }
            }
            .filter { entry in
                visibleProductStatuses.contains(normalizedOrderItemStatusTitle(for: entry).lowercased())
            }
            .sorted { lhs, rhs in
                let lhsPriority = orderItemStatusPriority(for: lhs)
                let rhsPriority = orderItemStatusPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.order.id != rhs.order.id {
                    return lhs.order.id > rhs.order.id
                }
                return lhs.item.id > rhs.item.id
            }
    }

    private var currentSectionIsEmpty: Bool {
        switch selectedSection {
        case .orders, .shipments:
            return displayedOrders.isEmpty
        case .products:
            return productEntries.isEmpty
        }
    }

    private var emptyStateTitle: String {
        switch selectedSection {
        case .orders:
            return "По текущему фильтру заказы не найдены"
        case .products:
            return "По текущему фильтру товары не найдены"
        case .shipments:
            return "Нет заказов в статусах На сборку или Собран"
        }
    }

    private var orderItemStatuses: [HomeStatus] {
        referenceData.statuses.filter { $0.statusType == "order_products" }
    }

    private var visibleProductStatuses: Set<String> {
        ["не обработан", "перемещение", "заказ поставщику", "заказано"]
    }

    private func isShipmentOrder(_ order: HomeOrder) -> Bool {
        guard let title = normalizedOrderStatusTitle(for: order) else { return false }
        return ["На сборку", "Собран"].contains(title)
    }

    private func normalizedOrderStatusTitle(for order: HomeOrder) -> String? {
        if let status = order.orderStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
            return status
        }
        return referenceData.statuses.first(where: { $0.id == order.orderStatusID })?.statusStatus
    }

    private func normalizedOrderItemStatusTitle(for entry: CRMOrderProductEntry) -> String {
        if let status = entry.item.orderItemStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
            return status
        }
        return orderItemStatuses.first(where: { $0.id == entry.item.orderItemStatusID })?.statusStatus ?? ""
    }

    private func orderItemStatusPriority(for entry: CRMOrderProductEntry) -> Int {
        switch normalizedOrderItemStatusTitle(for: entry).lowercased() {
        case "не обработан":
            return 0
        case "заказ поставщику":
            return 1
        case "заказано":
            return 2
        case "перемещение":
            return 3
        default:
            return 4
        }
    }

    private func currencyTitle(for currencyID: Int?) -> String {
        guard let currency = referenceData.currencies.first(where: { $0.id == currencyID }) else {
            return "USD"
        }
        if let sign = currency.currencySign, !sign.isEmpty {
            return sign
        }
        return currency.currencyName
    }

    private func documentKey(kind: String, id: Int) -> String {
        "\(kind):\(id)"
    }

    private func handleOrderItemStatusSelection(order: HomeOrder, itemID: Int, statusID: Int, promptForSupplier: Bool = false) {
        guard let item = order.items.first(where: { $0.id == itemID }) else { return }
        guard let status = orderItemStatuses.first(where: { $0.id == statusID }) else {
            onSelectOrderItemStatus(order, itemID, statusID, nil, nil, nil)
            return
        }

        if status.statusStatus == "Перемещение" {
            movementSelection = CRMMovementSelection(
                order: order,
                itemID: itemID,
                statusID: statusID,
                sourceEstablishmentID: item.orderItemSourceEstablishmentID,
                destinationEstablishmentID: item.orderItemDestinationEstablishmentID
            )
            return
        }

        if promptForSupplier && status.statusStatus == "Заказ поставщику" {
            supplierSelection = CRMSupplierSelection(order: order, itemID: itemID, statusID: statusID)
            supplierQuery = item.orderItemSupplier ?? ""
            supplierResults = []
            isSearchingSuppliers = true
            handleSupplierQueryChange(supplierQuery)
            return
        }

        onSelectOrderItemStatus(order, itemID, statusID, nil, nil, nil)
    }

    private func dismissSupplierSelection() {
        supplierSelection = nil
        supplierResults = []
        isSearchingSuppliers = false
    }

    private func clearSupplierQuery() {
        supplierQuery = ""
        handleSupplierQueryChange("")
    }

    private func applySupplierContact(_ contact: HomeContact) {
        let normalizedSupplier = contact.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSupplier.isEmpty, let supplierSelection else { return }

        supplierQuery = normalizedSupplier
        onSelectOrderItemStatus(
            supplierSelection.order,
            supplierSelection.itemID,
            supplierSelection.statusID,
            nil,
            nil,
            normalizedSupplier
        )
        dismissSupplierSelection()
    }

    private func handleSupplierQueryChange(_ query: String) {
        guard supplierSelection != nil else { return }

        isSearchingSuppliers = true
        let expectedQuery = query

        Task {
            let results = await onSearchSupplierContacts(expectedQuery)
            guard supplierSelection != nil, supplierQuery == expectedQuery else { return }
            supplierResults = results
            isSearchingSuppliers = false
        }
    }
}

enum CRMSection: String, CaseIterable, Identifiable {
    case orders = "Все заказы"
    case products = "Товары"
    case shipments = "Отгрузки"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .orders:
            return "list.bullet.clipboard"
        case .products:
            return "shippingbox"
        case .shipments:
            return "truck.box"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .orders:
            return "Все заказы"
        case .products:
            return "Товары"
        case .shipments:
            return "Отгрузки"
        }
    }
}

private struct CRMMovementSelection: Identifiable {
    let order: HomeOrder
    let itemID: Int
    let statusID: Int
    let sourceEstablishmentID: Int?
    let destinationEstablishmentID: Int?

    var id: String {
        "\(order.id)-\(itemID)-\(statusID)"
    }
}

private struct CRMSupplierSelection: Identifiable {
    let order: HomeOrder
    let itemID: Int
    let statusID: Int

    var id: String {
        "supplier-\(order.id)-\(itemID)-\(statusID)"
    }
}

private struct CRMOrderProductEntry: Identifiable, Hashable {
    let order: HomeOrder
    let item: HomeOrderItem

    var id: String {
        "\(order.id)-\(item.id)"
    }
}

private struct CRMOrderProductRow: View {
    let entry: CRMOrderProductEntry
    let itemStatuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void
    let onUpdateNote: (String?) -> Void

    @State private var noteText: String
    @State private var syncedNoteText: String
    @State private var noteSaveTask: Task<Void, Never>?
    @FocusState private var isNoteFocused: Bool

    init(
        entry: CRMOrderProductEntry,
        itemStatuses: [HomeStatus],
        currencyTitleProvider: @escaping (Int?) -> String,
        isSaving: Bool,
        onOpen: @escaping () -> Void,
        onSelectStatus: @escaping (Int) -> Void,
        onUpdateNote: @escaping (String?) -> Void
    ) {
        self.entry = entry
        self.itemStatuses = itemStatuses
        self.currencyTitleProvider = currencyTitleProvider
        self.isSaving = isSaving
        self.onOpen = onOpen
        self.onSelectStatus = onSelectStatus
        self.onUpdateNote = onUpdateNote

        let initialNote = entry.item.orderItemNote ?? ""
        _noteText = State(initialValue: initialNote)
        _syncedNoteText = State(initialValue: initialNote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.item.orderItemName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Заказ №\(entry.order.id) * \(orderEstablishmentTitle) * \(entry.item.orderItemQuantity) шт. * \(entry.item.orderItemPrice)\(currencyTitleProvider(entry.item.orderItemCurrencyID))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(alignment: .trailing, spacing: 4) {
                    CRMStatusMenu(
                        title: itemStatusTitle,
                        color: BusinessDocumentColors.statusColor(entry.item.orderItemStatusColor),
                        statuses: itemStatuses,
                        selectedStatusID: entry.item.orderItemStatusID,
                        size: .compact,
                        isDisabled: isSaving,
                        onSelect: onSelectStatus
                    )

                    if let statusSecondaryLine {
                        Text(statusSecondaryLine)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120, alignment: .trailing)
                    }
                }

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            TextField("Заметка", text: $noteText, axis: .horizontal)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .textFieldStyle(.plain)
                .focused($isNoteFocused)
                .lineLimit(1)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(height: 25)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: noteText) { _, newValue in
                    queueNoteSave(for: newValue)
                }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
        )
        .onChange(of: entry.item.orderItemNote ?? "") { oldValue, newValue in
            syncedNoteText = newValue
            if !isNoteFocused || noteText == oldValue {
                noteText = newValue
            }
        }
        .onDisappear {
            noteSaveTask?.cancel()
        }
    }

    private var itemStatusTitle: String {
        if let title = entry.item.orderItemStatus, !title.isEmpty {
            return title
        }
        return itemStatuses.first(where: { $0.id == entry.item.orderItemStatusID })?.statusStatus ?? "Статус"
    }

    private var orderEstablishmentTitle: String {
        let trimmedTitle = entry.order.orderEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return "Без точки"
    }

    private var statusSecondaryLine: String? {
        if let supplier = entry.item.orderItemSupplier?.trimmingCharacters(in: .whitespacesAndNewlines), !supplier.isEmpty {
            return supplier
        }

        let sourceName = entry.item.orderItemSourceEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationName = entry.item.orderItemDestinationEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceName, !sourceName.isEmpty,
              let destinationName, !destinationName.isEmpty,
              itemStatusTitle == "Перемещение" else {
            return nil
        }
        return "\(sourceName) -> \(destinationName)"
    }

    private func queueNoteSave(for value: String) {
        noteSaveTask?.cancel()

        let normalizedValue = normalizedNote(value)
        guard normalizedValue != normalizedNote(syncedNoteText) else { return }

        noteSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onUpdateNote(normalizedValue.isEmpty ? nil : normalizedValue)
            }
        }
    }

    private func normalizedNote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CRMOrderCardView: View {
    let order: HomeOrder
    let isShipmentMode: Bool
    let orderMethods: [HomeOrderMethod]
    let itemStatuses: [HomeStatus]
    let statuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void
    let onSelectItemStatus: (Int, Int) -> Void
    let onCollectShipmentItem: (Int) -> Void
    let onCompleteShipmentOrder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Заказ №\(order.id)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(orderSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                if isShipmentMode {
                    CRMShipmentOrderCompleteButton(
                        isDisabled: isSaving || !isReadyForShipmentCompletion,
                        action: onCompleteShipmentOrder
                    )
                } else {
                    CRMStatusMenu(
                        title: order.orderStatus ?? "Статус",
                        color: BusinessDocumentColors.statusColor(order.orderStatusColor),
                        statuses: statuses,
                        selectedStatusID: order.orderStatusID,
                        isDisabled: isSaving,
                        onSelect: onSelectStatus
                    )
                }
            }

            if !normalizedComment.isEmpty {
                Text(normalizedComment)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.white.opacity(0.34))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(order.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            if isShipmentMode {
                                CRMShipmentCollectButton(
                                    isCollected: itemStatusTitle(for: item) == "Собрано",
                                    isDisabled: isSaving,
                                    action: {
                                        onCollectShipmentItem(item.id)
                                    }
                                )
                            } else {
                                CRMStatusMenu(
                                    title: itemStatusTitle(for: item),
                                    color: BusinessDocumentColors.statusColor(item.orderItemStatusColor),
                                    statuses: itemStatuses,
                                    selectedStatusID: item.orderItemStatusID,
                                    size: .compact,
                                    isDisabled: isSaving,
                                    onSelect: { statusID in
                                        onSelectItemStatus(item.id, statusID)
                                    }
                                )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.orderItemName)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(item.orderItemQuantity) шт. * \(item.orderItemPrice)\(currencyTitleProvider(item.orderItemCurrencyID))")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()

                Text(orderTotalLine)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private var orderSubtitle: String {
        [order.orderEstablishmentName, methodTitle, order.orderCustomer]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " * ")
    }

    private var methodTitle: String? {
        let title = order.orderMethodName ?? orderMethods.first(where: { $0.id == order.orderMethodID })?.orderMethodName
        guard let title, !title.isEmpty else { return nil }
        guard let orderSubMethod = order.orderSubMethod, !orderSubMethod.isEmpty else {
            return title
        }
        return "\(title) * \(orderSubMethod)"
    }

    private var normalizedComment: String {
        order.orderInfo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var orderTotalLine: String {
        let totals = summarizedTotal(
            entries: order.items.map { (price: $0.orderItemPrice, quantity: $0.orderItemQuantity, currency: currencyTitleProvider($0.orderItemCurrencyID)) }
        )
        return totals.isEmpty ? "Итого: \(order.items.count) поз." : "Итого: \(totals)"
    }

    private var isReadyForShipmentCompletion: Bool {
        guard (order.orderStatus ?? "") != "Выполнен" else { return false }
        guard !order.items.isEmpty else { return false }
        return order.items.allSatisfy { itemStatusTitle(for: $0) == "Собрано" }
    }

    private func itemStatusTitle(for item: HomeOrderItem) -> String {
        if let status = item.orderItemStatus, !status.isEmpty {
            return status
        }
        return itemStatuses.first(where: { $0.id == item.orderItemStatusID })?.statusStatus ?? "Статус"
    }
}

private struct CRMShipmentCollectButton: View {
    let isCollected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Собран")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(buttonColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(buttonColor.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(buttonColor.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isCollected)
        .opacity(isDisabled && !isCollected ? 0.6 : 1)
    }

    private var buttonColor: Color {
        isCollected ? Color(red: 0.06, green: 0.46, blue: 0.43) : Color(red: 0.39, green: 0.40, blue: 0.95)
    }
}

private struct CRMShipmentOrderCompleteButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Выполнено")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundColor, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var foregroundColor: Color {
        isDisabled ? Color(uiColor: .systemGray) : Color(red: 0.09, green: 0.64, blue: 0.35)
    }

    private var backgroundColor: Color {
        isDisabled ? Color(uiColor: .systemGray5) : Color(red: 0.09, green: 0.64, blue: 0.35).opacity(0.14)
    }

    private var borderColor: Color {
        isDisabled ? Color(uiColor: .systemGray3) : Color(red: 0.09, green: 0.64, blue: 0.35).opacity(0.26)
    }
}

private struct CRMShipmentOrderCompletionConfirmation: Identifiable {
    let order: HomeOrder

    var id: Int { order.id }
}

private struct CRMInventoryCardView: View {
    let inventory: HomeInventory
    let statuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void

    var body: some View {
        CRMFlatDocumentCard(
            title: "Инвентаризация №\(inventory.id)",
            subtitle: [inventory.inventoryEstablishmentName, inventory.inventorySupplier]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " * "),
            comment: nil,
            statusTitle: inventory.inventoryStatus ?? "Статус",
            statusColor: BusinessDocumentColors.statusColor(inventory.inventoryStatusColor),
            statuses: statuses,
            selectedStatusID: inventory.inventoryStatusID,
            items: inventory.items.map {
                "\($0.inventoryItemName) * \($0.inventoryItemQuantity) шт. * \($0.inventoryItemCost)\(currencyTitleProvider($0.inventoryItemCurrencyID))"
            },
            totalLine: summarizedTotal(
                entries: inventory.items.map { (price: $0.inventoryItemCost, quantity: $0.inventoryItemQuantity, currency: currencyTitleProvider($0.inventoryItemCurrencyID)) }
            ),
            isSaving: isSaving,
            onOpen: onOpen,
            onSelectStatus: onSelectStatus
        )
    }
}

private struct CRMProductRegistrationCardView: View {
    let registration: HomeProductRegistration
    let statuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void

    var body: some View {
        CRMFlatDocumentCard(
            title: "Приемка №\(registration.id)",
            subtitle: [registration.productRegistrationEstablishmentName, registration.productRegistrationSupplier]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " * "),
            comment: nil,
            statusTitle: registration.productRegistrationStatus ?? "Статус",
            statusColor: BusinessDocumentColors.statusColor(registration.productRegistrationStatusColor),
            statuses: statuses,
            selectedStatusID: registration.productRegistrationStatusID,
            items: registration.items.map {
                "\($0.productRegistrationItemName) * \($0.productRegistrationItemQuantity) шт. * \($0.productRegistrationItemCost)\(currencyTitleProvider($0.productRegistrationItemCurrencyID))"
            },
            totalLine: summarizedTotal(
                entries: registration.items.map { (price: $0.productRegistrationItemCost, quantity: $0.productRegistrationItemQuantity, currency: currencyTitleProvider($0.productRegistrationItemCurrencyID)) }
            ),
            isSaving: isSaving,
            onOpen: onOpen,
            onSelectStatus: onSelectStatus
        )
    }
}

private struct CRMFlatDocumentCard: View {
    let title: String
    let subtitle: String
    let comment: String?
    let statusTitle: String
    let statusColor: Color
    let statuses: [HomeStatus]
    let selectedStatusID: Int
    let items: [String]
    let totalLine: String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                CRMStatusMenu(
                    title: statusTitle,
                    color: statusColor,
                    statuses: statuses,
                    selectedStatusID: selectedStatusID,
                    isDisabled: isSaving,
                    onSelect: onSelectStatus
                )
            }

            if let comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.white.opacity(0.34))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            HStack {
                Spacer()

                Text(totalLine.isEmpty ? "Итого: \(items.count) поз." : "Итого: \(totalLine)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

private struct CRMStatusMenu: View {
    enum Size {
        case regular
        case compact

        var titleFontSize: CGFloat {
            switch self {
            case .regular:
                return 11
            case .compact:
                return 10
            }
        }

        var chevronFontSize: CGFloat {
            switch self {
            case .regular:
                return 9
            case .compact:
                return 8
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular:
                return 10
            case .compact:
                return 9
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .regular:
                return 7
            case .compact:
                return 5
            }
        }
    }

    let title: String
    let color: Color
    let statuses: [HomeStatus]
    let selectedStatusID: Int?
    let size: Size
    let isDisabled: Bool
    let onSelect: (Int) -> Void

    init(
        title: String,
        color: Color,
        statuses: [HomeStatus],
        selectedStatusID: Int?,
        size: Size = .regular,
        isDisabled: Bool,
        onSelect: @escaping (Int) -> Void
    ) {
        self.title = title
        self.color = color
        self.statuses = statuses
        self.selectedStatusID = selectedStatusID
        self.size = size
        self.isDisabled = isDisabled
        self.onSelect = onSelect
    }

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
                    .font(.system(size: size.titleFontSize, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(size: size.chevronFontSize, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
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

struct CRMSupplierSelectionSheet: View {
    @Binding var query: String
    let results: [HomeContact]
    let isSearching: Bool
    let onQueryChange: (String) -> Void
    let onClose: () -> Void
    let onClear: () -> Void
    let onSelectContact: (HomeContact) -> Void
    let onCreateContact: () -> Void
    let onConfirm: () -> Void
    let onSkip: () -> Void

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Поставщик")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Можно выбрать поставщика из базы или ввести нового. Тап по существующему поставщику сразу сохранит его для товара.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.68))

                TextField("ИП Воробьев", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)

                if !query.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .onChange(of: query) { _, newValue in
                onQueryChange(newValue)
            }

            supplierResultsPanel

            HStack(spacing: 10) {
                Button(action: onSkip) {
                    Text("Пропустить")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Сохранить")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(red: 0.48, green: 0.84, blue: 0.60), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Text("Отмена")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(red: 0.78, green: 0.25, blue: 0.29), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.14, green: 0.15, blue: 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
        )
    }

    @ViewBuilder
    private var supplierResultsPanel: some View {
        if isSearching {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text(normalizedQuery.isEmpty ? "Загружаем поставщиков..." : "Ищем поставщиков...")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 120)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if results.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(normalizedQuery.isEmpty ? "Поставщики не найдены" : "Поставщик не найден")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(normalizedQuery.isEmpty
                     ? "В базе пока нет поставщиков. Можно ввести нового вручную и сохранить его."
                     : "Можно добавить нового поставщика в базу и сразу выбрать его для товара.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                if !normalizedQuery.isEmpty {
                    Button(action: onCreateContact) {
                        Text("Добавить в базу и выбрать")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { contact in
                        Button {
                            onSelectContact(contact)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.contactName)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let contactInfo = contact.contactInfo, !contactInfo.isEmpty {
                                    Text(contactInfo)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.68))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
}

private struct CRMMovementRouteSheet: View {
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
                        .background(Color(red: 0.78, green: 0.25, blue: 0.29), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .background(Color(red: 0.48, green: 0.84, blue: 0.60), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sourceEstablishmentID == nil || destinationEstablishmentID == nil || sourceEstablishmentID == destinationEstablishmentID)
                .opacity(sourceEstablishmentID == nil || destinationEstablishmentID == nil || sourceEstablishmentID == destinationEstablishmentID ? 0.55 : 1)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.14, green: 0.15, blue: 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
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

private struct CRMSectionBar: View {
    @Binding var selection: CRMSection

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CRMSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 17, weight: .bold))

                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selection == section ? AppTheme.primaryButtonText : AppTheme.secondaryButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        (selection == section ? AppTheme.primaryButtonBackground : AppTheme.secondaryButtonBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.accessibilityTitle)
            }
        }
    }
}

private func summarizedTotal(entries: [(price: String, quantity: Int, currency: String)]) -> String {
    guard !entries.isEmpty else { return "" }

    let currencies = Set(entries.map(\.currency))
    guard currencies.count == 1 else {
        return "\(entries.count) поз."
    }

    var total = Decimal.zero
    for entry in entries {
        let normalized = entry.price.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized) else {
            return "\(entries.count) поз."
        }
        total += value * Decimal(entry.quantity)
    }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2

    let number = NSDecimalNumber(decimal: total)
    let amount = formatter.string(from: number) ?? number.stringValue
    return "\(amount)\(currencies.first ?? "")"
}
