import SwiftUI
import UIKit

struct CRMChecklistSheet: View {
    enum Category: String, CaseIterable, Identifiable {
        case order
        case movement

        var id: String { rawValue }

        var title: String {
            switch self {
            case .order:
                return "Заказ"
            case .movement:
                return "Перемещение"
            }
        }

        var checkpointTitle: String {
            switch self {
            case .order:
                return "Заказано"
            case .movement:
                return "Забрал"
            }
        }
    }

    struct Entry: Identifiable {
        let order: HomeOrder
        let item: HomeOrderItem

        var id: String {
            "\(order.id)-\(item.id)"
        }
    }

    let orders: [HomeOrder]
    let establishments: [HomeEstablishment]
    let errorMessage: String?
    let updatingDocumentKey: String?
    let onClose: () -> Void
    let onToggleStarted: (HomeOrder, HomeOrderItem, Bool) -> Void
    let onComplete: (HomeOrder, HomeOrderItem) -> Void
    let onMoveToMovement: (HomeOrder, HomeOrderItem, Int, Int) -> Void
    let itemStatuses: [HomeStatus]
    let onSelectStatus: (HomeOrder, HomeOrderItem, Int, String?) -> Void
    let onSearchSupplierContacts: (String) async -> [HomeContact]

    @State private var selectedCategory: Category = .order
    @State private var statusSelection: Entry?
    @State private var supplierSelection: ChecklistSupplierSelection?
    @State private var supplierQuery = ""
    @State private var supplierResults: [HomeContact] = []
    @State private var isSearchingSuppliers = false
    @State private var activeAlert: ChecklistAlertContent?
    @State private var isPreparingCopy = false
    @State private var completionSelection: Entry?
    @State private var movementSelection: ChecklistMovementSelection?
    @State private var startedOverrides: [String: Bool] = [:]
    @State private var completedOverrides: [String: Bool] = [:]
    @State private var copyStartStartedEntryIDs: Set<String> = []
    @State private var supplierSnapshots: [String: String] = [:]

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Чек-лист")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Заказы и Перемещение")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(readableSecondaryTextColor)
                    }

                    Spacer()

                    if selectedCategory == .order {
                        Button(action: handleCopyButtonTap) {
                            HStack(spacing: 6) {
                                Image(systemName: isPreparingCopy ? "checkmark.circle" : "doc.on.doc")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(isPreparingCopy ? "Готово" : "Скопировать")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(orderEntries.isEmpty ? disabledControlTextColor : primaryControlTextColor)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(controlFillColor, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(orderEntries.isEmpty)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(Category.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedCategory == category ? primaryControlTextColor : readableSecondaryTextColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    selectedCategory == category
                                        ? selectedTabFillColor
                                        : controlFillColor,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(selectedCategory == category ? 0.30 : 0.18), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.red.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerRow(for: selectedCategory)

                        if selectedCategory == .movement {
                            movementContent
                        } else {
                            orderContent
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, AppTheme.PageLayout.bottomPadding)

            if let completionSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.completionSelection = nil
                    }

                ChecklistCompletionActionSheet(
                    onCancel: {
                        self.completionSelection = nil
                    },
                    onMoveToMovement: {
                        beginMovementFlow(for: completionSelection)
                    },
                    onConfirm: {
                        confirmCompletion(for: completionSelection)
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if let movementSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.movementSelection = nil
                    }

                ChecklistMovementRouteSheet(
                    establishments: establishments,
                    initialSourceEstablishmentID: movementSelection.sourceEstablishmentID,
                    initialDestinationEstablishmentID: movementSelection.destinationEstablishmentID,
                    onClose: {
                        self.movementSelection = nil
                    },
                    onConfirm: { sourceID, destinationID in
                        applyMovementSelection(movementSelection, sourceID: sourceID, destinationID: destinationID)
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if let statusSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.statusSelection = nil
                    }

                ChecklistStatusPickerSheet(
                    itemName: statusSelection.item.orderItemName,
                    statuses: itemStatuses,
                    onSelect: { statusID in
                        selectChecklistStatus(statusID, for: statusSelection)
                    },
                    onCancel: {
                        self.statusSelection = nil
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if supplierSelection != nil {
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
                    onClose: { dismissSupplierSelection() },
                    onClear: { clearSupplierQuery() },
                    onSelectContact: { contact in
                        let name = contact.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
                        supplierQuery = name
                        applyChecklistSupplier(name.isEmpty ? nil : name)
                    },
                    onCreateContact: {
                        let name = supplierQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        applyChecklistSupplier(name)
                    },
                    onConfirm: {
                        let name = supplierQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        applyChecklistSupplier(name.isEmpty ? nil : name)
                    },
                    onSkip: {
                        applyChecklistSupplier(nil)
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear(perform: reconcileCheckpointOverrides)
        .onChange(of: checklistCheckpointSignature) { _, _ in
            reconcileCheckpointOverrides()
        }
        .onChange(of: checklistSupplierSignature) { _, _ in
            reconcileCheckpointOverrides()
        }
        .alert(item: $activeAlert) { alert in
            let dismissPrimaryAction = {
                alert.primaryAction?()
                activeAlert = nil
            }
            let dismissSecondaryAction = {
                alert.secondaryButton?.action?()
                activeAlert = nil
            }
            if let secondaryButton = alert.secondaryButton {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text(alert.primaryButtonTitle), action: dismissPrimaryAction),
                    secondaryButton: secondaryButton.alertButton(action: dismissSecondaryAction)
                )
            } else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(alert.primaryButtonTitle), action: dismissPrimaryAction)
                )
            }
        }
    }

    private var orderEntries: [Entry] {
        orders.flatMap { order in
            order.items.compactMap { item in
                guard item.orderItemStatus == "Заказ поставщику" || item.orderItemStatus == "Заказано" else { return nil }
                return Entry(order: order, item: item)
            }
        }
        .sorted(by: orderEntryComparator)
    }

    /// id статуса «Заказано» (order_products), если он есть в справочнике.
    private var orderedStatusID: Int? {
        itemStatuses.first(where: { $0.statusStatus == "Заказано" })?.id
    }

    private var movementEntries: [Entry] {
        orders.flatMap { order in
            order.items.compactMap { item in
                guard item.orderItemStatus == "Перемещение" else { return nil }
                return Entry(order: order, item: item)
            }
        }
    }

    @ViewBuilder
    private var orderContent: some View {
        if orderEntries.isEmpty {
            emptyState(text: "Нет позиций в статусе Заказ поставщику")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groupedOrderEntries, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(readableSecondaryTextColor)

                        VStack(spacing: 10) {
                            ForEach(group.entries) { entry in
                                checklistRow(entry: entry, category: .order)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var movementContent: some View {
        if movementEntries.isEmpty {
            emptyState(text: "Нет позиций в статусе Перемещение")
        } else {
            let grouped = Dictionary(grouping: movementEntries, by: movementGroupTitle(for:))
            VStack(alignment: .leading, spacing: 14) {
                ForEach(grouped.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(key)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(readableSecondaryTextColor)
                        VStack(spacing: 10) {
                            ForEach(grouped[key] ?? []) { entry in
                                checklistRow(entry: entry, category: .movement)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var groupedOrderEntries: [(title: String, entries: [Entry])] {
        Dictionary(grouping: orderEntries, by: supplierTitle(for:))
            .keys
            .sorted(by: supplierTitleComparator)
            .map { key in
                (title: key, entries: (Dictionary(grouping: orderEntries, by: supplierTitle(for:))[key] ?? []).sorted(by: orderEntryComparator))
            }
    }

    private func movementGroupTitle(for entry: Entry) -> String {
        let from = entry.item.orderItemSourceEstablishmentName ?? "Не указано"
        let to = entry.item.orderItemDestinationEstablishmentName ?? "Не указано"
        return "\(from) -> \(to)"
    }

    private func headerRow(for category: Category) -> some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(maxWidth: .infinity)

            Text(category.checkpointTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(readableSecondaryTextColor)
                .frame(width: 82)

            Text("Выполнено")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(readableSecondaryTextColor)
                .frame(width: 82)
        }
    }

    private func checklistRow(entry: Entry, category: Category) -> some View {
        let isSaving = updatingDocumentKey == "order:\(entry.order.id)"
        let isStarted = currentStartedState(for: entry) || (category == .order && entry.item.orderItemStatus == "Заказано")
        let isCompleted = currentCompletedState(for: entry)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.item.orderItemName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Заказ №\(entry.order.id) * \(entry.order.orderCustomer)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            checklistMarkButton(
                isActive: isStarted,
                isDisabled: isSaving,
                action: {
                    if category == .order {
                        if isStarted {
                            // Уже «Заказано» — выбрать любой статус (в т.ч. форс-мажор).
                            statusSelection = entry
                        } else if let orderedStatusID {
                            startedOverrides[entry.id] = true
                            onSelectStatus(entry.order, entry.item, orderedStatusID, nil)
                        }
                    } else {
                        let nextStarted = !isStarted
                        startedOverrides[entry.id] = nextStarted
                        if !nextStarted {
                            completedOverrides[entry.id] = false
                        }
                        onToggleStarted(entry.order, entry.item, nextStarted)
                    }
                }
            )
            .frame(width: 82)

            checklistMarkButton(
                isActive: isCompleted,
                isDisabled: isSaving || isCompleted || isPreparingCopy,
                action: {
                    presentCompletionConfirmation(for: entry, category: category)
                }
            )
            .frame(width: 82)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func checklistMarkButton(isActive: Bool, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isActive ? "checkmark.square.fill" : "square")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isActive ? Color(red: 0.27, green: 0.83, blue: 0.48) : inactiveMarkColor)
                .frame(width: 42, height: 42)
                .background(controlFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var readableSecondaryTextColor: Color {
        Color.white.opacity(0.88)
    }

    private var primaryControlTextColor: Color {
        Color.white.opacity(0.96)
    }

    private var disabledControlTextColor: Color {
        Color.white.opacity(0.52)
    }

    private var controlFillColor: Color {
        Color.white.opacity(0.12)
    }

    private var selectedTabFillColor: Color {
        Color.white.opacity(0.18)
    }

    private var inactiveMarkColor: Color {
        Color.black.opacity(0.82)
    }

    private var selectedEntriesForCopy: [Entry] {
        orderEntries.filter { entry in
            currentStartedState(for: entry) && !copyStartStartedEntryIDs.contains(entry.id)
        }
    }

    private var checklistCheckpointSignature: [String] {
        (orderEntries + movementEntries).map {
            "\($0.id):\($0.item.orderItemCheckpointStarted):\($0.item.orderItemCheckpointCompleted)"
        }
    }

    private var checklistSupplierSignature: [String] {
        orderEntries.map {
            "\($0.id):\(supplierTitle(for: $0))"
        }
    }

    private func handleCopyButtonTap() {
        if isPreparingCopy {
            finalizeCopyOrderChecklist()
            return
        }

        copyStartStartedEntryIDs = Set(
            orderEntries.compactMap { entry in
                currentStartedState(for: entry) ? entry.id : nil
            }
        )
        isPreparingCopy = true
    }

    private func presentCompletionConfirmation(for entry: Entry, category: Category) {
        guard category == .order else {
            activeAlert = ChecklistAlertContent(
                title: "Подтвердите выполнение",
                message: "Отметить позицию как выполненную? Это защищает от случайных нажатий.",
                primaryButtonTitle: "Подтвердить",
                primaryAction: {
                    startedOverrides[entry.id] = true
                    completedOverrides[entry.id] = true
                    onComplete(entry.order, entry.item)
                },
                secondaryButton: ChecklistAlertButton(
                    title: "Отмена",
                    role: .cancel,
                    action: nil
                )
            )
            return
        }

        completionSelection = entry
    }

    private func confirmCompletion(for entry: Entry) {
        completionSelection = nil
        startedOverrides[entry.id] = true
        completedOverrides[entry.id] = true
        onComplete(entry.order, entry.item)
    }

    private func beginMovementFlow(for entry: Entry) {
        completionSelection = nil
        movementSelection = ChecklistMovementSelection(
            entry: entry,
            sourceEstablishmentID: entry.item.orderItemSourceEstablishmentID,
            destinationEstablishmentID: entry.item.orderItemDestinationEstablishmentID
        )
    }

    private func applyMovementSelection(_ selection: ChecklistMovementSelection, sourceID: Int, destinationID: Int) {
        movementSelection = nil
        isPreparingCopy = false
        copyStartStartedEntryIDs.remove(selection.entry.id)
        startedOverrides[selection.entry.id] = false
        completedOverrides[selection.entry.id] = false
        onMoveToMovement(selection.entry.order, selection.entry.item, sourceID, destinationID)
    }

    private func selectChecklistStatus(_ statusID: Int, for entry: Entry) {
        statusSelection = nil
        let statusName = itemStatuses.first(where: { $0.id == statusID })?.statusStatus

        // «Перемещение» = товар есть на другом складе, нужен маршрут (откуда → куда) —
        // уводим в отдельный флоу выбора маршрута, а не просто ставим статус.
        if statusName == "Перемещение" {
            beginMovementFlow(for: entry)
            return
        }

        // «Заказ поставщику» — нужно выбрать поставщика.
        if statusName == "Заказ поставщику" {
            beginSupplierFlow(for: entry, statusID: statusID)
            return
        }

        let isOrdered = statusName == "Заказано"
        startedOverrides[entry.id] = isOrdered
        if !isOrdered {
            completedOverrides[entry.id] = false
        }
        onSelectStatus(entry.order, entry.item, statusID, nil)
    }

    private func beginSupplierFlow(for entry: Entry, statusID: Int) {
        supplierSelection = ChecklistSupplierSelection(entry: entry, statusID: statusID)
        supplierQuery = entry.item.orderItemSupplier ?? ""
        supplierResults = []
        isSearchingSuppliers = true
        handleSupplierQueryChange(supplierQuery)
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

    private func dismissSupplierSelection() {
        supplierSelection = nil
        supplierResults = []
        isSearchingSuppliers = false
    }

    private func clearSupplierQuery() {
        supplierQuery = ""
        handleSupplierQueryChange("")
    }

    private func applyChecklistSupplier(_ supplierName: String?) {
        guard let supplierSelection else { return }
        let entry = supplierSelection.entry
        let statusID = supplierSelection.statusID
        // Статус «Заказ поставщику» — позиция больше не «Заказано».
        startedOverrides[entry.id] = false
        completedOverrides[entry.id] = false
        onSelectStatus(entry.order, entry.item, statusID, supplierName)
        dismissSupplierSelection()
    }

    private func finalizeCopyOrderChecklist() {
        guard !orderEntries.isEmpty else { return }

        if selectedEntriesForCopy.isEmpty {
            activeAlert = ChecklistAlertContent(
                title: "Нет новых позиций",
                message: "Отметьте хотя бы одну новую позицию в колонке Заказано после нажатия Скопировать. Уже отмеченные ранее товары повторно в список не добавляются.",
                secondaryButton: ChecklistAlertButton(
                    title: "Отменить",
                    role: .cancel,
                    action: resetCopyPreparation
                )
            )
            return
        }

        UIPasteboard.general.string = copyText
        isPreparingCopy = false
        copyStartStartedEntryIDs = []
        activeAlert = ChecklistAlertContent(
            title: "Список скопирован",
            message: "Скопированы только новые отмеченные позиции. Список можно вставить в почту, Telegram или WhatsApp поставщику."
        )
    }

    private var copyText: String {
        Dictionary(grouping: selectedEntriesForCopy, by: supplierTitle(for:))
            .keys
            .sorted(by: supplierTitleComparator)
            .map { key in
                let entries = (Dictionary(grouping: selectedEntriesForCopy, by: supplierTitle(for:))[key] ?? [])
                    .sorted(by: orderEntryComparator)
                let itemsText = entries
                    .map { "- \($0.item.orderItemName) * \($0.item.orderItemQuantity) шт." }
                    .joined(separator: "\n")
                return "\(key)\n\(itemsText)"
            }
            .map { group in
                group
            }
            .joined(separator: "\n\n")
    }

    private func supplierTitle(for entry: Entry) -> String {
        let trimmedTitle = entry.item.orderItemSupplier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return "Без поставщика"
    }

    private func supplierTitleComparator(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Без поставщика" { return false }
        if rhs == "Без поставщика" { return true }
        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private func orderEntryComparator(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lhsSupplier = supplierTitle(for: lhs)
        let rhsSupplier = supplierTitle(for: rhs)
        if lhsSupplier != rhsSupplier {
            return supplierTitleComparator(lhsSupplier, rhsSupplier)
        }
        if lhs.order.id != rhs.order.id {
            return lhs.order.id > rhs.order.id
        }
        let lhsStarted = currentStartedState(for: lhs)
        let rhsStarted = currentStartedState(for: rhs)
        if lhsStarted != rhsStarted {
            return lhsStarted && !rhsStarted
        }
        return lhs.item.id > rhs.item.id
    }

    private func currentStartedState(for entry: Entry) -> Bool {
        startedOverrides[entry.id] ?? entry.item.orderItemCheckpointStarted
    }

    private func currentCompletedState(for entry: Entry) -> Bool {
        completedOverrides[entry.id] ?? entry.item.orderItemCheckpointCompleted
    }

    private func reconcileCheckpointOverrides() {
        let allEntries = orderEntries + movementEntries
        let existingIDs = Set(allEntries.map(\.id))

        let currentSupplierSnapshots = Dictionary(uniqueKeysWithValues: orderEntries.map { ($0.id, supplierTitle(for: $0)) })
        for entry in orderEntries {
            guard let previousSupplier = supplierSnapshots[entry.id] else { continue }
            let currentSupplier = currentSupplierSnapshots[entry.id] ?? supplierTitle(for: entry)
            guard previousSupplier != currentSupplier, currentStartedState(for: entry) else { continue }

            startedOverrides[entry.id] = false
            completedOverrides[entry.id] = false
            copyStartStartedEntryIDs.remove(entry.id)
            onToggleStarted(entry.order, entry.item, false)
        }

        supplierSnapshots = currentSupplierSnapshots

        startedOverrides = startedOverrides.reduce(into: [:]) { result, item in
            guard existingIDs.contains(item.key) else { return }
            guard let entry = allEntries.first(where: { $0.id == item.key }) else { return }
            if entry.item.orderItemCheckpointStarted != item.value {
                result[item.key] = item.value
            }
        }

        completedOverrides = completedOverrides.reduce(into: [:]) { result, item in
            guard existingIDs.contains(item.key) else { return }
            guard let entry = allEntries.first(where: { $0.id == item.key }) else { return }
            if entry.item.orderItemCheckpointCompleted != item.value {
                result[item.key] = item.value
            }
        }
    }

    private func resetCopyPreparation() {
        isPreparingCopy = false
        copyStartStartedEntryIDs = []
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(readableSecondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }
}

private struct ChecklistAlertContent: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var primaryButtonTitle: String = "Понятно"
    var primaryAction: (() -> Void)? = nil
    var secondaryButton: ChecklistAlertButton? = nil
}

private struct ChecklistAlertButton {
    enum Role {
        case `default`
        case cancel
        case destructive
    }

    let title: String
    let role: Role
    let action: (() -> Void)?

    func alertButton(action overrideAction: (() -> Void)? = nil) -> Alert.Button {
        let buttonAction = overrideAction ?? action
        switch role {
        case .default:
            return .default(Text(title), action: buttonAction)
        case .cancel:
            return .cancel(Text(title), action: buttonAction)
        case .destructive:
            return .destructive(Text(title), action: buttonAction)
        }
    }
}

private struct ChecklistMovementSelection: Identifiable {
    let entry: CRMChecklistSheet.Entry
    let sourceEstablishmentID: Int?
    let destinationEstablishmentID: Int?

    var id: String { entry.id }
}

private struct ChecklistSupplierSelection: Identifiable {
    let entry: CRMChecklistSheet.Entry
    let statusID: Int

    var id: String { "supplier-\(entry.id)-\(statusID)" }
}

private struct ChecklistStatusPickerSheet: View {
    let itemName: String
    let statuses: [HomeStatus]
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Сменить статус")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(itemName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(statuses, id: \.id) { status in
                        Button {
                            onSelect(status.id)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(BusinessDocumentColors.statusColor(status.statusColor))
                                    .frame(width: 10, height: 10)
                                Text(status.statusStatus)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)

            Button(action: onCancel) {
                Text("Отмена")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
    }
}

private struct ChecklistCompletionActionSheet: View {
    let onCancel: () -> Void
    let onMoveToMovement: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Подтвердите выполнение")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Можно сразу отметить позицию как выполненную или перевести ее в перемещение с выбором маршрута.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            VStack(spacing: 10) {
                Button(action: onMoveToMovement) {
                    Text("В перемещение")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Подтвердить")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(red: 0.48, green: 0.84, blue: 0.60), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(red: 0.78, green: 0.25, blue: 0.29), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
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
}

private struct ChecklistMovementRouteSheet: View {
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
