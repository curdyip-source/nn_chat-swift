import SwiftUI

struct InventoryDetailView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var store: HomeStore

    let inventoryID: Int
    let onClose: () -> Void

    @State private var inventory: HomeInventory?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        BusinessDocumentDetailContainer(
            title: "Инвентаризация #\(inventoryID)",
            isLoading: isLoading,
            isSaving: isSaving,
            errorMessage: errorMessage,
            onClose: onClose,
            headerContent: {
                if let inventory {
                    BusinessDocumentStatusButtons(
                        statuses: store.referenceData.statuses.filter { $0.statusType == "inventory" },
                        selectedStatusID: inventory.inventoryStatusID,
                        isSaving: isSaving,
                        onSelect: updateStatus
                    )
                }
            },
            content: {
                if let inventory {
                    VStack(spacing: 16) {
                        BusinessDocumentInfoSection(
                            title: "Параметры",
                            rows: inventoryInfoRows(for: inventory)
                        )
                        BusinessDocumentItemsSection(
                            title: "Позиции",
                            items: inventory.items.map {
                                BusinessDocumentItemViewModel(
                                    id: $0.id,
                                    name: $0.inventoryItemName,
                                    article: $0.inventoryItemArticle,
                                    quantity: $0.inventoryItemQuantity,
                                    cost: $0.inventoryItemCost,
                                    currencyTitle: currencyTitle(for: $0.inventoryItemCurrencyID)
                                )
                            }
                        )
                    }
                }
            }
        )
        .task(id: inventoryID) {
            await loadInventory()
        }
    }

    private func loadInventory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            inventory = try await store.fetchInventory(accessToken: session.currentAccessToken, inventoryID: inventoryID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateStatus(_ statusID: Int) {
        guard inventory?.inventoryStatusID != statusID else { return }

        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                inventory = try await store.updateInventoryStatus(accessToken: session.currentAccessToken, inventoryID: inventoryID, statusID: statusID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inventoryInfoRows(for inventory: HomeInventory) -> [BusinessDocumentInfoRowModel] {
        var rows = [
            BusinessDocumentInfoRowModel(title: "Точка", value: inventory.inventoryEstablishmentName ?? "Точка"),
            BusinessDocumentInfoRowModel(title: "Создана", value: formattedDate(inventory.inventoryCreatedAt))
        ]

        if let supplier = inventory.inventorySupplier, !supplier.isEmpty {
            rows.insert(BusinessDocumentInfoRowModel(title: "Поставщик", value: supplier), at: 1)
        }

        return rows
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

    private func formattedDate(_ rawValue: String?) -> String {
        guard let date = HomeMessageDateParser.parse(rawValue) else {
            return rawValue ?? "-"
        }
        return BusinessDocumentFormatters.dateTime.string(from: date)
    }
}

struct ProductRegistrationDetailView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var store: HomeStore

    let productRegistrationID: Int
    let onClose: () -> Void

    @State private var registration: HomeProductRegistration?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        BusinessDocumentDetailContainer(
            title: "Приемка #\(productRegistrationID)",
            isLoading: isLoading,
            isSaving: isSaving,
            errorMessage: errorMessage,
            onClose: onClose,
            headerContent: {
                if let registration {
                    BusinessDocumentStatusButtons(
                        statuses: store.referenceData.statuses.filter { $0.statusType == "product_registration" },
                        selectedStatusID: registration.productRegistrationStatusID,
                        isSaving: isSaving,
                        onSelect: updateStatus
                    )
                }
            },
            content: {
                if let registration {
                    VStack(spacing: 16) {
                        BusinessDocumentInfoSection(
                            title: "Параметры",
                            rows: [
                                BusinessDocumentInfoRowModel(title: "Точка", value: registration.productRegistrationEstablishmentName ?? "Точка"),
                                BusinessDocumentInfoRowModel(title: "Поставщик", value: registration.productRegistrationSupplier ?? "-"),
                                BusinessDocumentInfoRowModel(title: "Создана", value: formattedDate(registration.productRegistrationCreatedAt))
                            ]
                        )
                        BusinessDocumentItemsSection(
                            title: "Позиции",
                            items: registration.items.map {
                                BusinessDocumentItemViewModel(
                                    id: $0.id,
                                    name: $0.productRegistrationItemName,
                                    article: $0.productRegistrationItemArticle,
                                    quantity: $0.productRegistrationItemQuantity,
                                    cost: $0.productRegistrationItemCost,
                                    currencyTitle: currencyTitle(for: $0.productRegistrationItemCurrencyID)
                                )
                            }
                        )
                    }
                }
            }
        )
        .task(id: productRegistrationID) {
            await loadRegistration()
        }
    }

    private func loadRegistration() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            registration = try await store.fetchProductRegistration(accessToken: session.currentAccessToken, productRegistrationID: productRegistrationID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateStatus(_ statusID: Int) {
        guard registration?.productRegistrationStatusID != statusID else { return }

        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }

            do {
                registration = try await store.updateProductRegistrationStatus(accessToken: session.currentAccessToken, productRegistrationID: productRegistrationID, statusID: statusID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

    private func formattedDate(_ rawValue: String?) -> String {
        guard let date = HomeMessageDateParser.parse(rawValue) else {
            return rawValue ?? "-"
        }
        return BusinessDocumentFormatters.dateTime.string(from: date)
    }
}

struct BusinessDocumentDetailContainer<HeaderContent: View, Content: View>: View {
    let title: String
    let isLoading: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onClose: () -> Void
    let headerActionSystemImage: String?
    let onHeaderAction: (() -> Void)?
    let scrollTargetID: String?
    let scrollRequest: Int
    let headerHorizontalPadding: CGFloat
    let contentHorizontalPadding: CGFloat
    @ViewBuilder let headerContent: () -> HeaderContent
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        isLoading: Bool,
        isSaving: Bool,
        errorMessage: String?,
        onClose: @escaping () -> Void,
        headerActionSystemImage: String? = nil,
        onHeaderAction: (() -> Void)? = nil,
        scrollTargetID: String? = nil,
        scrollRequest: Int = 0,
        headerHorizontalPadding: CGFloat = 16,
        contentHorizontalPadding: CGFloat = 16,
        @ViewBuilder headerContent: @escaping () -> HeaderContent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onClose = onClose
        self.headerActionSystemImage = headerActionSystemImage
        self.onHeaderAction = onHeaderAction
        self.scrollTargetID = scrollTargetID
        self.scrollRequest = scrollRequest
        self.headerHorizontalPadding = headerHorizontalPadding
        self.contentHorizontalPadding = contentHorizontalPadding
        self.headerContent = headerContent
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.05), in: Circle())
                    }

                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))

                    Spacer()

                    if isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Сохраняем")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }

                    if let headerActionSystemImage, let onHeaderAction {
                        Button(action: onHeaderAction) {
                            Image(systemName: headerActionSystemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color.black.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                headerContent()
            }
            .padding(.horizontal, headerHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(
                Color(UIColor.systemBackground)
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            )

            if isLoading {
                Spacer()
                ProgressView("Загружаем документ...")
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            content()
                        }
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: scrollRequest) { _, _ in
                        guard let scrollTargetID else { return }
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(scrollTargetID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }
}

struct BusinessDocumentStatusButtons: View {
    let statuses: [HomeStatus]
    let selectedStatusID: Int
    let isSaving: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(statuses) { status in
                let isSelected = status.id == selectedStatusID

                Button {
                    guard !isSaving else { return }
                    onSelect(status.id)
                } label: {
                    Text(status.statusStatus)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color(uiColor: .label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isSelected ? BusinessDocumentColors.statusColor(status.statusColor) : Color(uiColor: .secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BusinessDocumentStaticPressButtonStyle())
                .disabled(isSaving)
            }
        }
    }
}

struct BusinessDocumentInfoSection: View {
    let title: String
    let rows: [BusinessDocumentInfoRowModel]
    let labelWidth: CGFloat

    init(title: String, rows: [BusinessDocumentInfoRowModel], labelWidth: CGFloat = 88) {
        self.title = title
        self.rows = rows
        self.labelWidth = labelWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)

                    Text(row.value)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct BusinessDocumentItemsSection: View {
    let title: String
    let items: [BusinessDocumentItemViewModel]

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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                if let article = item.article, !article.isEmpty {
                                    Text(article)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(item.totalTitle)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            BusinessDocumentMetricChip(title: "Кол-во", value: "\(item.quantity)")
                            BusinessDocumentMetricChip(title: "Цена", value: "\(item.cost) \(item.currencyTitle)")
                        }
                    }
                    .padding(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct BusinessDocumentMetricChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BusinessDocumentInfoRowModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct BusinessDocumentItemViewModel: Identifiable {
    let id: Int
    let name: String
    let article: String?
    let quantity: Int
    let cost: String
    let currencyTitle: String

    var totalTitle: String {
        let normalizedCost = cost.replacingOccurrences(of: ",", with: ".")
        let total = (Double(normalizedCost) ?? 0) * Double(quantity)
        return "Итого: \(total.formatted(.number.precision(.fractionLength(2)))) \(currencyTitle)"
    }
}

enum BusinessDocumentColors {
    static func statusColor(_ rawValue: String?) -> Color {
        guard let rawValue else {
            return Color(red: 0.96, green: 0.44, blue: 0.27)
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "green":
            return Color(red: 0.16, green: 0.52, blue: 0.31)
        case "orange":
            return Color(red: 0.78, green: 0.44, blue: 0.12)
        case "blue":
            return Color(red: 0.20, green: 0.40, blue: 0.78)
        default:
            if normalized.hasPrefix("#"), let color = Color(hex: normalized) {
                return color
            }
            return Color(red: 0.96, green: 0.44, blue: 0.27)
        }
    }
}

enum BusinessDocumentFormatters {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()
}

private struct BusinessDocumentStaticPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 || hex.count == 8, let int = UInt64(hex, radix: 16) else {
            return nil
        }

        let a, r, g, b: UInt64
        if hex.count == 8 {
            (a, r, g, b) = (int >> 24, int >> 16 & 0xff, int >> 8 & 0xff, int & 0xff)
        } else {
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xff, int & 0xff)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}