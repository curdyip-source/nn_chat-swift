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
    let errorMessage: String?
    let updatingDocumentKey: String?
    let onClose: () -> Void
    let onToggleStarted: (HomeOrder, HomeOrderItem, Bool) -> Void
    let onComplete: (HomeOrder, HomeOrderItem) -> Void

    @State private var selectedCategory: Category = .order
    @State private var activeAlert: ChecklistAlertContent?
    @State private var isPreparingCopy = false
    @State private var startedOverrides: [String: Bool] = [:]
    @State private var completedOverrides: [String: Bool] = [:]
    @State private var copyStartStartedEntryIDs: Set<String> = []
    @State private var supplierSnapshots: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Чек-лист")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Заказы и Перемещение")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(orderEntries.isEmpty ? Color.secondary : Color.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
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
                            .foregroundStyle(selectedCategory == category ? Color.black : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                selectedCategory == category
                                    ? Color.white
                                    : Color(uiColor: .secondarySystemFill),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                guard item.orderItemStatus == "Заказ поставщику" else { return nil }
                return Entry(order: order, item: item)
            }
        }
        .sorted(by: orderEntryComparator)
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
                            .foregroundStyle(.secondary)

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
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(width: 82)

            Text("Выполнено")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 82)
        }
    }

    private func checklistRow(entry: Entry, category: Category) -> some View {
        let isSaving = updatingDocumentKey == "order:\(entry.order.id)"
        let isStarted = currentStartedState(for: entry)
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
                    let nextStarted = !isStarted
                    startedOverrides[entry.id] = nextStarted
                    if !nextStarted {
                        completedOverrides[entry.id] = false
                    }
                    onToggleStarted(entry.order, entry.item, nextStarted)
                }
            )
            .frame(width: 82)

            checklistMarkButton(
                isActive: isCompleted,
                isDisabled: isSaving || isCompleted || isPreparingCopy,
                action: {
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
                .foregroundStyle(isActive ? Color(red: 0.27, green: 0.83, blue: 0.48) : Color.white.opacity(0.72))
                .frame(width: 42, height: 42)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
            .foregroundStyle(.secondary)
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
