import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Чек-лист")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Позиции со статусами Заказ и Перемещение")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(Category.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedCategory == category ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                selectedCategory == category
                                    ? Color.white
                                    : Color.white.opacity(0.08),
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
            .frame(maxWidth: .infinity, maxHeight: 420, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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

    private var orderEntries: [Entry] {
        orders.flatMap { order in
            order.items.compactMap { item in
                guard item.orderItemStatus == "Заказ" else { return nil }
                return Entry(order: order, item: item)
            }
        }
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
            emptyState(text: "Нет позиций в статусе Заказ")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(orderEntries) { entry in
                    checklistRow(entry: entry, category: .order)
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
                            .foregroundStyle(.white.opacity(0.78))
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
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 82)

            Text("Выполнено")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 82)
        }
    }

    private func checklistRow(entry: Entry, category: Category) -> some View {
        let isSaving = updatingDocumentKey == "order:\(entry.order.id)"

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.item.orderItemName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Заказ №\(entry.order.id) * \(entry.order.orderCustomer)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            checklistMarkButton(
                isActive: entry.item.orderItemCheckpointStarted,
                isDisabled: isSaving,
                action: {
                    onToggleStarted(entry.order, entry.item, !entry.item.orderItemCheckpointStarted)
                }
            )
            .frame(width: 82)

            checklistMarkButton(
                isActive: entry.item.orderItemCheckpointCompleted,
                isDisabled: isSaving || entry.item.orderItemCheckpointCompleted,
                action: {
                    onComplete(entry.order, entry.item)
                }
            )
            .frame(width: 82)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func checklistMarkButton(isActive: Bool, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isActive ? "checkmark.square.fill" : "square")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isActive ? Color(red: 0.27, green: 0.83, blue: 0.48) : Color.white.opacity(0.72))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }
}
