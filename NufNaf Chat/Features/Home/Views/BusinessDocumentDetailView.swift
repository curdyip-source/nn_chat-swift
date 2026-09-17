import SwiftUI
import UIKit

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
    @State private var dragOffsetX: CGFloat = 0
    @State private var isInteractiveDismissInProgress = false
    @State private var measuredWidth: CGFloat = 0
    @State private var isClosing = false

    let title: String
    let isLoading: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onClose: () -> Void
    let onInteractiveDismissStart: () -> Void
    let headerActionSystemImage: String?
    let onHeaderAction: (() -> Void)?
    /// Второе действие в шапке — слева от основного (в заказе это история).
    let headerSecondaryActionSystemImage: String?
    let onHeaderSecondaryAction: (() -> Void)?
    let prefersDarkHeader: Bool
    let scrollTargetID: String?
    let scrollRequest: Int
    /// Над документом открыт модальный лист (форма задачи, накладная СДЭК и т.п.).
    /// Тогда автоскролл к блоку над клавиатурой не нужен: клавиатуру поднимает лист,
    /// а не поле документа, и страница под ним уезжала бы в чужое место.
    let ignoresKeyboardScroll: Bool
    let headerHorizontalPadding: CGFloat
    let contentHorizontalPadding: CGFloat
    @ViewBuilder let headerContent: () -> HeaderContent
    @ViewBuilder let content: () -> Content

    // Optional external view (e.g. the comment dock) that lives outside this container but must
    // slide together with it — kept in lockstep with dragOffsetX.
    private let dockOffset: Binding<CGFloat>?

    init(
        title: String,
        isLoading: Bool,
        isSaving: Bool,
        errorMessage: String?,
        dockOffset: Binding<CGFloat>? = nil,
        onClose: @escaping () -> Void,
        onInteractiveDismissStart: @escaping () -> Void = {},
        headerActionSystemImage: String? = nil,
        onHeaderAction: (() -> Void)? = nil,
        headerSecondaryActionSystemImage: String? = nil,
        onHeaderSecondaryAction: (() -> Void)? = nil,
        prefersDarkHeader: Bool = false,
        scrollTargetID: String? = nil,
        scrollRequest: Int = 0,
        ignoresKeyboardScroll: Bool = false,
        headerHorizontalPadding: CGFloat = 16,
        contentHorizontalPadding: CGFloat = 16,
        @ViewBuilder headerContent: @escaping () -> HeaderContent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.dockOffset = dockOffset
        self.onClose = onClose
        self.onInteractiveDismissStart = onInteractiveDismissStart
        self.headerActionSystemImage = headerActionSystemImage
        self.onHeaderAction = onHeaderAction
        self.headerSecondaryActionSystemImage = headerSecondaryActionSystemImage
        self.onHeaderSecondaryAction = onHeaderSecondaryAction
        self.prefersDarkHeader = prefersDarkHeader
        self.scrollTargetID = scrollTargetID
        self.scrollRequest = scrollRequest
        self.ignoresKeyboardScroll = ignoresKeyboardScroll
        self.headerHorizontalPadding = headerHorizontalPadding
        self.contentHorizontalPadding = contentHorizontalPadding
        self.headerContent = headerContent
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: { closeWithSlide() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(prefersDarkHeader ? Color.white : Color.primary)
                                    .frame(width: 38, height: 38)
                                    .background((prefersDarkHeader ? Color.white.opacity(0.14) : Color.black.opacity(0.05)), in: Circle())
                            }

                            Text(title)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(prefersDarkHeader ? Color.white : Color.primary)

                            Spacer()

                            if isSaving {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Сохраняем")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(prefersDarkHeader ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background((prefersDarkHeader ? Color.white.opacity(0.14) : Color(uiColor: .secondarySystemBackground)), in: Capsule())
                            }

                            if let headerSecondaryActionSystemImage, let onHeaderSecondaryAction {
                                Button(action: onHeaderSecondaryAction) {
                                    Image(systemName: headerSecondaryActionSystemImage)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(prefersDarkHeader ? Color.white : Color.primary)
                                        .frame(width: 38, height: 38)
                                        .background((prefersDarkHeader ? Color.white.opacity(0.14) : Color.black.opacity(0.05)), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }

                            if let headerActionSystemImage, let onHeaderAction {
                                Button(action: onHeaderAction) {
                                    Image(systemName: headerActionSystemImage)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(prefersDarkHeader ? Color.white : Color.primary)
                                        .frame(width: 38, height: 38)
                                        .background((prefersDarkHeader ? Color.white.opacity(0.14) : Color.black.opacity(0.05)), in: Circle())
                                }
                            .buttonStyle(.plain)
                            }
                        }

                        headerContent()
                    }
                    .padding(.horizontal, headerHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .background {
                        if prefersDarkHeader {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.black, location: 0),
                                    .init(color: Color.black, location: 0.84),
                                    .init(color: Color.black.opacity(0.98), location: 0.95),
                                    .init(color: Color.black.opacity(0.10), location: 0.99),
                                    .init(color: Color.black.opacity(0.04), location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                        } else {
                            Color(UIColor.systemBackground)
                                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                        }
                    }

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
                                withAnimation(.easeOut(duration: 0.16)) {
                                    proxy.scrollTo(scrollTargetID, anchor: .bottom)
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                                // Скроллим блок над клавиатурой при её появлении — быстро,
                                // блок встаёт на место раньше, чем клавиатура доедет.
                                let screenHeight = UIApplication.shared.connectedScenes
                                    .compactMap { $0 as? UIWindowScene }
                                    .first?.screen.bounds.height ?? 0
                                guard !ignoresKeyboardScroll,
                                      let scrollTargetID,
                                      let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
                                      endFrame.minY < screenHeight - 1 else { return }
                                withAnimation(.easeOut(duration: 0.16)) {
                                    proxy.scrollTo(scrollTargetID, anchor: .bottom)
                                }
                                // Повтор на следующем ранлупе: с самого верха страницы первый
                                // scrollTo перебивается лейаут-проходом клавиатуры и не доезжает.
                                // Если первый сработал — это no-op, скорость не меняется.
                                DispatchQueue.main.async {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        proxy.scrollTo(scrollTargetID, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .offset(x: dragOffsetX)
            .shadow(color: .black.opacity(interactiveShadowOpacity(containerWidth: geometry.size.width)), radius: 18, x: -6, y: 0)
            .contentShape(Rectangle())
            .simultaneousGesture(backSwipeGesture(containerWidth: geometry.size.width))
            .onAppear { measuredWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, width in measuredWidth = width }
        }
        // Светлый экран документа/заказа (фон + читаемый тёмный текст) в тёмном приложении.
        .environment(\.colorScheme, .light)
    }

    private func backSwipeGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onChanged { value in
                guard shouldTrackBackSwipe(value) else { return }
                if !isInteractiveDismissInProgress {
                    // Сразу при распознавании свайпа-выхода прячем клавиатуру,
                    // чтобы она уезжала до/во время перехода, а не после.
                    onInteractiveDismissStart()
                }
                isInteractiveDismissInProgress = true
                applyDragOffset(interactiveOffset(for: value.translation.width, containerWidth: containerWidth))
            }
            .onEnded { value in
                guard shouldTrackBackSwipe(value) else {
                    resetInteractiveDismiss()
                    return
                }

                guard shouldCloseForBackSwipe(value) else {
                    resetInteractiveDismiss()
                    return
                }

                closeWithSlide(containerWidth: containerWidth)
            }
    }

    private func interactiveShadowOpacity(containerWidth: CGFloat) -> Double {
        guard isInteractiveDismissInProgress else { return 0 }
        let progress = min(max(dragOffsetX / max(containerWidth, 1), 0), 1)
        return 0.10 * (1 - progress)
    }

    private func interactiveOffset(for translationWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let clampedWidth = max(translationWidth, 0)
        let maxWidth = max(containerWidth, 1)
        return min(clampedWidth, maxWidth)
    }

    private func shouldTrackBackSwipe(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x <= 28
            && value.translation.width > 0
            && abs(value.translation.width) > abs(value.translation.height)
    }

    private func shouldCloseForBackSwipe(_ value: DragGesture.Value) -> Bool {
        let translationWidth = value.translation.width
        let predictedWidth = value.predictedEndTranslation.width
        return shouldTrackBackSwipe(value) && (translationWidth >= 96 || predictedWidth >= 180)
    }

    /// Single close path for both the back button and the edge swipe: dismiss the keyboard,
    /// slide the card off to the right, then remove it. The removal transition is `.identity`,
    /// so this manual slide is the only close animation (no double-animation / stuck transition).
    private func closeWithSlide(containerWidth: CGFloat? = nil) {
        guard !isClosing else { return }
        isClosing = true
        // Dismiss any keyboard NOW (incl. edit-sheet fields) in its OWN frame, so it slides
        // straight down on its own curve — not captured by the card's horizontal spring (which
        // flung it sideways) and not cut off by teardown (which made it snap away after a beat).
        onInteractiveDismissStart() // clears @FocusState so SwiftUI doesn't re-assert focus
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        let screenWidth = max(containerWidth ?? measuredWidth, 1)
        // Next runloop: keyboard dismissal already owns this frame, so the slide won't animate it.
        DispatchQueue.main.async {
            withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.9)) {
                applyDragOffset(screenWidth)
            }
        }
        // Remove only after the keyboard has had time to animate fully down, so the focused field
        // isn't torn down mid-dismiss (which is what made the keyboard snap instead of slide).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            onClose()
        }
    }

    private func resetInteractiveDismiss() {
        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.86)) {
            applyDragOffset(0)
        }
        isInteractiveDismissInProgress = false
    }

    /// Move the card and any attached external dock together, so the comment field slides with the
    /// rest of the screen instead of lingering behind.
    private func applyDragOffset(_ value: CGFloat) {
        dragOffsetX = value
        dockOffset?.wrappedValue = value
    }
}

struct BusinessDocumentStatusButtons: View {
    let statuses: [HomeStatus]
    let selectedStatusID: Int
    let isSaving: Bool
    let prefersDarkAppearance: Bool
    let onSelect: (Int) -> Void

    init(
        statuses: [HomeStatus],
        selectedStatusID: Int,
        isSaving: Bool,
        prefersDarkAppearance: Bool = false,
        onSelect: @escaping (Int) -> Void
    ) {
        self.statuses = statuses
        self.selectedStatusID = selectedStatusID
        self.isSaving = isSaving
        self.prefersDarkAppearance = prefersDarkAppearance
        self.onSelect = onSelect
    }

    // Rows of 3, rendered non-lazily — a LazyVGrid materialises its cells on its own pass, so
    // during the open slide the status buttons popped in "in place" instead of moving with the card.
    private var statusRows: [[HomeStatus]] {
        stride(from: 0, to: statuses.count, by: 3).map { Array(statuses[$0 ..< min($0 + 3, statuses.count)]) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(statusRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { status in
                        statusButton(status)
                    }
                    if row.count < 3 {
                        ForEach(0 ..< (3 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: 40)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusButton(_ status: HomeStatus) -> some View {
        let isSelected = status.id == selectedStatusID
        Button {
            guard !isSaving else { return }
            onSelect(status.id)
        } label: {
            Text(status.statusStatus)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : (prefersDarkAppearance ? Color.white.opacity(0.94) : Color(uiColor: .label)))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    isSelected
                        ? BusinessDocumentColors.statusColor(status.statusColor)
                        : (prefersDarkAppearance ? Color.white.opacity(0.12) : Color(uiColor: .secondarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isSelected
                                ? Color.clear
                                : (prefersDarkAppearance ? Color.white.opacity(0.28) : Color.black.opacity(0.06)),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BusinessDocumentStaticPressButtonStyle())
        .disabled(isSaving)
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
                            BusinessDocumentMetricChip(title: "Цена", value: "\(AppAmount.grouped(item.cost)) \(item.currencyTitle)")
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
        return "Итого: \(AppAmount.grouped(String(format: "%.2f", total))) \(currencyTitle)"
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
        case "red":
            return Color(red: 0.86, green: 0.18, blue: 0.18)
        case "gray", "grey":
            return Color(uiColor: .systemGray)
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