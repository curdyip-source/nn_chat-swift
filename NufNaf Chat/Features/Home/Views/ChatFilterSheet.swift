import SwiftUI

struct ChatFilterSheet: View {
    @Binding var filter: HomeChatFilterState

    let messages: [HomeMessage]
    let referenceData: HomeReferenceDataResponse
    let onClose: () -> Void
    let onReset: () -> Void

    @State private var dragOffsetY: CGFloat = 0

    private let allMonths = Array(1 ... 12)
    private let statusGroupOrder = ["orders", "product_registration", "inventory"]

    var body: some View {
        GeometryReader { proxy in
            content(containerHeight: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func content(containerHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            dragHandle(containerHeight: containerHeight)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Фильтр")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Сущности, точки, статусы и период")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterSection("Показ") {
                        filterToggleCard(title: "Скрыть выполненные") {
                            Toggle("", isOn: $filter.hideCompleted)
                                .labelsHidden()
                                .tint(Color(red: 0.96, green: 0.44, blue: 0.27))
                        }

                        filterToggleCard(title: "Скрыть отмененные") {
                            Toggle("", isOn: $filter.hideCancelled)
                                .labelsHidden()
                                .tint(Color(red: 0.96, green: 0.44, blue: 0.27))
                        }
                    }

                    sectionDivider

                    filterSection("Сущности") {
                        filterFlow(HomeChatFilterKind.allCases, id: \.id) { kind in
                            filterChip(
                                title: kind.title,
                                isActive: isActive(kind, in: filter.kinds),
                                action: {
                                    filter.kinds = toggledSelection(kind, current: filter.kinds, allValues: HomeChatFilterKind.allCases)
                                }
                            )
                        }
                    }

                    if !referenceData.orderMethods.isEmpty {
                        filterSection("Методы") {
                            filterFlow(referenceData.orderMethods, id: \.id) { method in
                                filterChip(
                                    title: method.orderMethodName,
                                    isActive: isActive(method.id, in: filter.orderMethodIDs),
                                    action: {
                                        let allIDs = referenceData.orderMethods.map(\.id)
                                        filter.orderMethodIDs = toggledSelection(method.id, current: filter.orderMethodIDs, allValues: allIDs)
                                    }
                                )
                            }
                        }
                    }

                    filterSection("Точки") {
                        filterFlow(referenceData.establishments, id: \.id) { establishment in
                            filterChip(
                                title: establishment.establishmentName,
                                isActive: isActive(establishment.id, in: filter.establishmentIDs),
                                action: {
                                    let allIDs = referenceData.establishments.map(\.id)
                                    filter.establishmentIDs = toggledSelection(establishment.id, current: filter.establishmentIDs, allValues: allIDs)
                                }
                            )
                        }
                    }

                    if !availableStatusGroups.isEmpty {
                        filterSection("Статусы") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(availableStatusGroups, id: \.type) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(group.title)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.72))

                                        filterFlow(group.statuses, id: \.id) { status in
                                            filterChip(
                                                title: status.statusStatus,
                                                isActive: isActive(status.id, in: filter.statusIDs),
                                                action: {
                                                    let allIDs = availableStatuses.map(\.id)
                                                    filter.statusIDs = toggledSelection(status.id, current: filter.statusIDs, allValues: allIDs)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    filterSection("Год") {
                        Menu {
                            ForEach(availableYears, id: \.self) { year in
                                Button {
                                    filter.year = year
                                } label: {
                                    Text(String(year))
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(filter.year))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    filterSection("Месяцы") {
                        filterFlow(allMonths, id: \.self) { month in
                            filterChip(
                                title: monthTitle(month),
                                isActive: isActive(month, in: filter.months),
                                action: {
                                    filter.months = toggledSelection(month, current: filter.months, allValues: allMonths)
                                }
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 460)

            HStack(spacing: 10) {
                Button(action: onReset) {
                    Text("Сброс")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Text("Закрыть")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
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
        .offset(y: dragOffsetY)
    }

    private func dragHandle(containerHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .gesture(closeGesture(containerHeight: containerHeight))
    }

    private func closeGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                dragOffsetY = value.translation.height
            }
            .onEnded { value in
                let shouldClose = value.translation.height > 120 || value.predictedEndTranslation.height > 220
                if shouldClose {
                    withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.9)) {
                        dragOffsetY = max(containerHeight, value.translation.height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        dragOffsetY = 0
                        onClose()
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.86)) {
                        dragOffsetY = 0
                    }
                }
            }
    }

    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = Set(messages.compactMap { message in
            message.parsedCreatedAt.map { Calendar.current.component(.year, from: $0) }
        } + [currentYear, filter.year])
        return years.sorted(by: >)
    }

    private var availableStatuses: [HomeStatus] {
        referenceData.statuses.filter { ["orders", "inventory", "product_registration"].contains($0.statusType) }
    }

    private var availableStatusGroups: [(type: String, title: String, statuses: [HomeStatus])] {
        statusGroupOrder.compactMap { type in
            let statuses = availableStatuses.filter { $0.statusType == type }
            guard !statuses.isEmpty else { return nil }
            return (type: type, title: statusGroupTitle(type), statuses: statuses)
        }
    }

    private func monthTitle(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.shortMonthSymbols[month - 1].capitalized
    }

    private func statusGroupTitle(_ rawValue: String) -> String {
        switch rawValue {
        case "orders":
            return "Заказ"
        case "inventory":
            return "Инвентаризация"
        case "product_registration":
            return "Приемка"
        default:
            return rawValue
        }
    }

    private func isActive<Value: Hashable>(_ value: Value, in set: Set<Value>) -> Bool {
        set.isEmpty || set.contains(value)
    }

    private func toggledSelection<Value: Hashable>(_ value: Value, current: Set<Value>, allValues: [Value]) -> Set<Value> {
        let allSet = Set(allValues)

        if current.isEmpty {
            return [value]
        }

        var updated = current
        if updated.contains(value) {
            updated.remove(value)
        } else {
            updated.insert(value)
        }

        if updated.isEmpty || updated == allSet {
            return []
        }
        return updated
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            content()
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private func filterToggleCard<Trailing: View>(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            Spacer(minLength: 12)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func filterFlow<Data: RandomAccessCollection, ID: Hashable, Content: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(data, id: id, content: content)
        }
    }

    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.84))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .padding(.horizontal, 10)
                .background(
                    isActive
                        ? Color(red: 0.96, green: 0.44, blue: 0.27)
                        : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}