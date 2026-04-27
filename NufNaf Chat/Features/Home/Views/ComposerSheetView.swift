//
//  ComposerSheetView.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import SwiftUI
import UIKit

struct ComposerSheetView: View {
    @EnvironmentObject private var session: AppSession
    @State private var selectedEstablishmentID: Int?
    @State private var selectedOrderMethodID: Int?
    @State private var selectedOrderSubMethod: String?
    @State private var counterpartyName = ""
    @State private var info = ""
    @State private var searchQuery = ""
    @State private var searchResults: [HomeProduct] = []
    @State private var customArticle = ""
    @State private var customName = ""
    @State private var customPrice = "0.00"
    @State private var selectedItems: [HomeComposerItemDraft] = []
    @State private var isSubmitting = false
    @State private var isSearchingProducts = false
    @State private var isSearchOverlayPresented = false
    @State private var isCreateProductOverlayPresented = false
    @State private var isCreatingProduct = false
    @State private var productFormErrorMessage: String?
    @State private var submitErrorMessage: String?
    @State private var selectedSection: ComposerSection = .info
    @FocusState private var focusedField: FocusField?

    let kind: HomeComposerKind
    let editingOrder: HomeOrder?
    let editingItemStatusIDs: [Int: Int?]
    @ObservedObject var store: HomeStore
    let onClose: () -> Void
    let onOrderUpdated: ((HomeOrder) -> Void)?

    init(
        kind: HomeComposerKind,
        editingOrder: HomeOrder? = nil,
        editingItemStatusIDs: [Int: Int?] = [:],
        store: HomeStore,
        onClose: @escaping () -> Void,
        onOrderUpdated: ((HomeOrder) -> Void)? = nil
    ) {
        self.kind = kind
        self.editingOrder = editingOrder
        self.editingItemStatusIDs = editingItemStatusIDs
        self.store = store
        self.onClose = onClose
        self.onOrderUpdated = onOrderUpdated

        _selectedEstablishmentID = State(initialValue: editingOrder?.orderEstablishmentID)
        _selectedOrderMethodID = State(initialValue: editingOrder?.orderMethodID)
        _selectedOrderSubMethod = State(initialValue: editingOrder?.orderSubMethod)
        _counterpartyName = State(initialValue: editingOrder?.orderCustomer ?? "")
        _info = State(initialValue: editingOrder?.orderInfo ?? "")
        _selectedItems = State(initialValue: editingOrder?.items.map(HomeComposerItemDraft.init) ?? [])
    }

    private enum ComposerSection: String, CaseIterable, Identifiable {
        case info = "Информация"
        case products = "Список товаров"

        var id: String { rawValue }
    }

    private enum FocusField: Hashable {
        case counterparty
        case info
        case search
        case customArticle
        case customName
        case customPrice
        case itemPrice(UUID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    sheetHeader

                    GeometryReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                if let submitErrorMessage, !submitErrorMessage.isEmpty {
                                    Text(submitErrorMessage)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }

                                composerContent
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: proxy.size.height - 12, alignment: .top)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 16)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissKeyboard()
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                    }
                }

                if isCreateProductOverlayPresented {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissKeyboard()
                            dismissProductOverlays(clearSearch: false)
                        }
                }

                if isCreateProductOverlayPresented {
                    createProductOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerFooter
            }
            .background(Color(UIColor.systemBackground))
            .onAppear {
                syncSelectedOrderSubMethod()
                applyDefaultCurrencyToItems()
            }
            .onChange(of: selectedOrderMethodID) { _, _ in
                syncSelectedOrderSubMethod()
            }
            .onChange(of: store.referenceData.currencies) { _, _ in
                applyDefaultCurrencyToItems()
            }
            .onChange(of: selectedSection) { _, newValue in
                if newValue != .products {
                    dismissProductOverlays(clearSearch: false)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .animation(.easeInOut(duration: 0.18), value: isCreateProductOverlayPresented || isSearchOverlayPresented)
        }
    }

    @ViewBuilder
    private var composerContent: some View {
        if selectedSection == .info {
            if showsCounterpartyField {
                composerField(title: counterpartyTitle, text: $counterpartyName, placeholder: counterpartyPlaceholder, focus: .counterparty)
            }

            if kind == .order {
                composerField(title: "Информация", text: $info, placeholder: "г. Москва, улица Восьмая 6", focus: .info)
                composerDivider
            } else if showsCounterpartyField {
                composerDivider
            }

            if !store.referenceData.establishments.isEmpty {
                composerChoiceGroup(
                    items: store.referenceData.establishments,
                    selectedID: selectedEstablishmentID,
                    title: nil,
                    layout: .equalWidthRow,
                    value: { $0.establishmentName },
                    onSelect: { selectedEstablishmentID = $0.id }
                )
            }

            if kind == .order, !store.referenceData.orderMethods.isEmpty {
                composerDivider

                composerChoiceGroup(
                    items: store.referenceData.orderMethods,
                    selectedID: selectedOrderMethodID,
                    title: nil,
                    layout: .threeColumnGrid,
                    value: { $0.orderMethodName },
                    onSelect: { selectedOrderMethodID = $0.id }
                )

                if !availableOrderSubMethods.isEmpty {
                    composerDivider

                    composerSubMethodGroup(
                        title: "Подспособ",
                        options: availableOrderSubMethods,
                        selectedValue: selectedOrderSubMethod,
                        onSelect: { selectedOrderSubMethod = $0 }
                    )
                }
            }
        }

        if selectedSection == .products {
            VStack(alignment: .leading, spacing: 12) {
                Text("Корзина")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                productSearchField

                if isSearchOverlayPresented {
                    searchResultsPanel
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if selectedItems.isEmpty {
                    Text("Добавьте товары через поиск или создайте новый товар из нижнего окна.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    composerDivider

                    Text("Добавленные позиции")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach($selectedItems) { $item in
                            compactSelectedItemCard($item)
                        }
                    }
                }
            }
        }
    }

    private var composerFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)

            VStack(spacing: 0) {
                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(actionButtonTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(StaticPressButtonStyle())
                .disabled(isSubmitDisabled)
                .opacity(isSubmitDisabled ? 0.45 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(Color(UIColor.systemBackground))
        }
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sheetTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Button("Закрыть", action: onClose)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

            composerSectionPicker
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var selectedOrderMethod: HomeOrderMethod? {
        store.referenceData.orderMethods.first(where: { $0.id == selectedOrderMethodID })
    }

    private var availableOrderSubMethods: [String] {
        selectedOrderMethod?.orderMethodSubMethods ?? []
    }

    private var isSubmitDisabled: Bool {
        isSubmitting || selectedItems.isEmpty || selectedEstablishmentID == nil || !hasRequiredFields || (kind == .order && selectedOrderMethodID == nil)
    }

    private var hasRequiredFields: Bool {
        switch kind {
        case .order:
            return !counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .inventory:
            return true
        case .productRegistration:
            return !counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var showsCounterpartyField: Bool {
        kind != .inventory
    }

    private var counterpartyTitle: String {
        kind == .order ? "Клиент" : "Поставщик"
    }

    private var counterpartyPlaceholder: String {
        kind == .order ? "Марина" : "ООО Восток"
    }

    private var actionButtonTitle: String {
        if editingOrder != nil {
            return "Сохранить заказ"
        }

        switch kind {
        case .order:
            return "Создать заказ"
        case .inventory:
            return "Создать инвентаризацию"
        case .productRegistration:
            return "Создать приемку"
        }
    }

    private var sheetTitle: String {
        if let editingOrder {
            return "Редактирование заказа №\(editingOrder.id)"
        }
        return kind.title
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableCurrencies: [HomeCurrency] {
        store.referenceData.currencies
    }

    private var defaultCurrencyID: Int? {
        availableCurrencies.first?.id
    }

    private var isCreateProductDisabled: Bool {
        isCreatingProduct
            || customArticle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || customPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerSectionPicker: some View {
        GeometryReader { proxy in
            let controlWidth = max(proxy.size.width - 4, 0)
            let knobWidth = controlWidth / 2

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .systemGray4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .frame(width: knobWidth)
                    .padding(2)
                    .offset(x: selectedSection == .info ? 0 : knobWidth)

                HStack(spacing: 0) {
                    sectionToggleButton(.info)
                    sectionToggleButton(.products)
                }
            }
        }
        .frame(height: 32)
    }

    private var productSearchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Поиск товара")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Артикул или название", text: $searchQuery)
                    .focused($focusedField, equals: .search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.primary)

                if !searchQuery.isEmpty {
                    Button {
                        clearSearchQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(inputFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(inputFieldBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                presentSearchOverlay()
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == .search {
                presentSearchOverlay()
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            handleSearchQueryChange(newValue)
        }
    }

    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if normalizedSearchQuery.isEmpty {
                Text("Начните вводить артикул или название товара.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isSearchingProducts {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    ProgressView()
                    Text("Ищем товары...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
            } else if searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Товар не найден")
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    Text("Можно создать новый товар и сразу добавить его в корзину.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Button("Создать новый товар") {
                        openCreateProductOverlay()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(searchResults, id: \.id) { product in
                            Button {
                                appendProductToBasket(product)
                                dismissProductOverlays(clearSearch: true)
                            } label: {
                                Text(product.productName)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(inputFieldBorder, lineWidth: 1)
                )
        )
    }

    private var createProductOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            overlayGrabber

            HStack {
                Text("Новый товар")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer(minLength: 12)

                Button("Назад") {
                    isCreateProductOverlayPresented = false
                    isSearchOverlayPresented = true
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(Capsule())
            }

            composerField(title: "Артикул", text: $customArticle, placeholder: "000010", focus: .customArticle)
            composerField(title: "Название", text: $customName, placeholder: "Название товара", focus: .customName)
            composerField(title: "Цена", text: $customPrice, placeholder: "0.00", keyboard: .decimalPad, focus: .customPrice)

            if let productFormErrorMessage, !productFormErrorMessage.isEmpty {
                Text(productFormErrorMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await createCustomProduct()
                }
            } label: {
                HStack(spacing: 10) {
                    if isCreatingProduct {
                        ProgressView()
                            .tint(.white)
                    }

                    Text("Сохранить и добавить в корзину")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(StaticPressButtonStyle())
            .disabled(isCreateProductDisabled)
            .opacity(isCreateProductDisabled ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var overlayGrabber: some View {
        Capsule()
            .fill(Color.black.opacity(0.14))
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity)
    }

    private enum ChoiceGroupLayout {
        case equalWidthRow
        case threeColumnGrid
    }

    private var secondaryButtonBackground: Color {
        Color(uiColor: .secondarySystemFill)
    }

    private var secondaryButtonText: Color {
        Color(uiColor: .label)
    }

    private var selectedButtonBackground: Color {
        Color(red: 0.96, green: 0.44, blue: 0.27)
    }

    private struct StaticPressButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.82 : 1)
        }
    }

    private func sectionToggleButton(_ section: ComposerSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
        } label: {
            Text(section.rawValue)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private func composerButtonLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .padding(14)
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func presentSearchOverlay() {
        isSearchOverlayPresented = true
        if normalizedSearchQuery.count >= 2 {
            handleSearchQueryChange(searchQuery)
        }
    }

    private func dismissProductOverlays(clearSearch: Bool) {
        isCreateProductOverlayPresented = false
        isSearchingProducts = false
        productFormErrorMessage = nil
        dismissKeyboard()

        if clearSearch {
            isSearchOverlayPresented = false
            searchQuery = ""
            searchResults = []
        }
    }

    private func openCreateProductOverlay() {
        isSearchOverlayPresented = false
        isCreateProductOverlayPresented = true
        productFormErrorMessage = nil

        if customArticle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !normalizedSearchQuery.contains(" ") {
            customArticle = normalizedSearchQuery
        }
        if customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customName = normalizedSearchQuery
        }
    }

    private func handleSearchQueryChange(_ query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isSearchOverlayPresented || focusedField == .search else {
            return
        }

        guard normalizedQuery.count >= 2 else {
            searchResults = []
            isSearchingProducts = false
            isSearchOverlayPresented = true
            return
        }

        isSearchingProducts = true
        let expectedQuery = query

        Task {
            let results = await store.searchProducts(accessToken: session.currentAccessToken, query: expectedQuery)
            guard searchQuery == expectedQuery else { return }
            searchResults = results
            isSearchingProducts = false
        }
    }

    private func clearSearchQuery() {
        searchQuery = ""
        searchResults = []
        isSearchingProducts = false
        isSearchOverlayPresented = true
        focusedField = .search
    }

    private func appendProductToBasket(_ product: HomeProduct) {
        selectedItems.append(
            HomeComposerItemDraft(
                productID: product.id,
                article: product.productArticle,
                name: product.productName,
                quantity: 1,
                price: product.productCostUSD,
                currencyID: defaultCurrencyID
            )
        )
    }

    private func clearCustomProductForm() {
        customArticle = ""
        customName = ""
        customPrice = "0.00"
        productFormErrorMessage = nil
    }

    private func createCustomProduct() async {
        let article = customArticle.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = customPrice.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !article.isEmpty, !name.isEmpty, !price.isEmpty else {
            productFormErrorMessage = "Заполните артикул, название и цену"
            return
        }

        isCreatingProduct = true
        defer { isCreatingProduct = false }

        do {
            let createdProduct = try await store.createProduct(accessToken: session.currentAccessToken, article: article, name: name, costUSD: price)
            appendProductToBasket(createdProduct)
            clearCustomProductForm()
            dismissProductOverlays(clearSearch: true)
        } catch {
            productFormErrorMessage = error.localizedDescription
        }
    }

    private func composerField(title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default, focus: FocusField? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Group {
                if let focus {
                    TextField(placeholder, text: text)
                        .focused($focusedField, equals: focus)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .keyboardType(keyboard)
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .padding(14)
            .background(inputFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(inputFieldBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func compactSelectedItemCard(_ item: Binding<HomeComposerItemDraft>) -> some View {
        let itemValue = item.wrappedValue

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(itemValue.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    focusedField = nil
                    selectedItems.removeAll { $0.id == itemValue.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                compactQuantityControl(item: item)

                TextField("Цена", text: item.price)
                    .focused($focusedField, equals: .itemPrice(itemValue.id))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .padding(.horizontal, 10)
                    .background(inputFieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(inputFieldBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !availableCurrencies.isEmpty {
                    Menu {
                        ForEach(availableCurrencies) { currency in
                            Button {
                                item.wrappedValue.currencyID = currency.id
                            } label: {
                                Text(currencyMenuTitle(for: currency))
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currencyButtonTitle(for: itemValue.currencyID))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                        .frame(width: 78, height: 36)
                        .background(inputFieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(inputFieldBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }

    private func compactQuantityControl(item: Binding<HomeComposerItemDraft>) -> some View {
        HStack(spacing: 0) {
            Button {
                item.wrappedValue.quantity = max(1, item.wrappedValue.quantity - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)

            Text("\(item.wrappedValue.quantity)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(minWidth: 34)

            Button {
                item.wrappedValue.quantity = min(999, item.wrappedValue.quantity + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
        .background(inputFieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(inputFieldBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func currencyButtonTitle(for currencyID: Int?) -> String {
        guard let currency = availableCurrencies.first(where: { $0.id == currencyID }) else {
            return "Валюта"
        }
        if let currencySign = currency.currencySign, !currencySign.isEmpty {
            return currencySign
        }
        return currency.currencyName
    }

    private func currencyMenuTitle(for currency: HomeCurrency) -> String {
        if let currencySign = currency.currencySign, !currencySign.isEmpty {
            return "\(currency.currencyName) (\(currencySign))"
        }
        return currency.currencyName
    }

    private func applyDefaultCurrencyToItems() {
        guard let defaultCurrencyID else { return }
        selectedItems = selectedItems.map { item in
            guard item.currencyID == nil else { return item }
            var updatedItem = item
            updatedItem.currencyID = defaultCurrencyID
            return updatedItem
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var inputFieldBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    private var inputFieldBorder: Color {
        Color(uiColor: .separator).opacity(0.35)
    }

    private var composerDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private func composerSubMethodGroup(title: String, options: [String], selectedValue: String?, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selectedValue == option

                    Button {
                        onSelect(option)
                    } label: {
                        Text(option)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : secondaryButtonText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(isSelected ? selectedButtonBackground : secondaryButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(StaticPressButtonStyle())
                }
            }
        }
    }

    private func composerChoiceGroup<Item: Identifiable>(items: [Item], selectedID: Int?, title: String?, layout: ChoiceGroupLayout, value: @escaping (Item) -> String, onSelect: @escaping (Item) -> Void) -> some View where Item.ID == Int {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            switch layout {
            case .equalWidthRow:
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        let isSelected = item.id == selectedID

                        Button {
                            onSelect(item)
                        } label: {
                            Text(value(item))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white : secondaryButtonText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(isSelected ? selectedButtonBackground : secondaryButtonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(StaticPressButtonStyle())
                    }
                }

            case .threeColumnGrid:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(items) { item in
                        let isSelected = item.id == selectedID

                        Button {
                            onSelect(item)
                        } label: {
                            Text(value(item))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white : secondaryButtonText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(isSelected ? selectedButtonBackground : secondaryButtonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(StaticPressButtonStyle())
                    }
                }
            }
        }
    }

    private func submit() async {
        guard let selectedEstablishmentID else { return }
        isSubmitting = true
        submitErrorMessage = nil
        defer { isSubmitting = false }

        if let editingOrder {
            do {
                let updatedOrder = try await store.updateOrder(
                    accessToken: session.currentAccessToken,
                    orderID: editingOrder.id,
                    request: HomeOrderUpdateRequest(
                        orderEstablishmentID: selectedEstablishmentID,
                        orderMethodID: selectedOrderMethodID ?? editingOrder.orderMethodID,
                        orderSubMethod: selectedOrderSubMethod,
                        orderCustomer: normalized(counterpartyName) ?? "",
                        orderInfo: normalized(info) ?? "",
                        orderStatusID: editingOrder.orderStatusID,
                        items: selectedItems.map {
                            let existingItem = resolveEditingOrderItem(for: $0)
                            return HomeOrderItemCreateRequest(
                                productID: $0.productID,
                                productArticle: $0.productID == nil ? normalized($0.article) : nil,
                                productName: $0.productID == nil ? (normalized($0.name) ?? "Позиция") : nil,
                                orderItemQuantity: max($0.quantity, 1),
                                orderItemPrice: normalizedPrice($0.price),
                                orderItemStatusID: resolveEditingOrderItemStatusID(for: $0),
                                orderItemSourceEstablishmentID: existingItem?.orderItemSourceEstablishmentID,
                                orderItemDestinationEstablishmentID: existingItem?.orderItemDestinationEstablishmentID,
                                orderItemCurrencyID: $0.currencyID,
                                orderItemCheckpointStarted: existingItem?.orderItemCheckpointStarted ?? false,
                                orderItemCheckpointCompleted: existingItem?.orderItemCheckpointCompleted ?? false
                            )
                        }
                    )
                )
                dismissProductOverlays(clearSearch: true)
                onOrderUpdated?(updatedOrder)
                onClose()
            } catch {
                submitErrorMessage = error.localizedDescription
            }
            return
        }

        await store.submitComposer(
            kind: kind,
            accessToken: session.currentAccessToken,
            currentUser: userForSubmission,
            establishmentID: selectedEstablishmentID,
            orderMethodID: selectedOrderMethodID,
            orderSubMethod: selectedOrderSubMethod,
            counterpartyName: counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines),
            info: info.trimmingCharacters(in: .whitespacesAndNewlines),
            items: selectedItems
        )
        dismissProductOverlays(clearSearch: true)
        onClose()
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedPrice(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0.00" : trimmed.replacingOccurrences(of: ",", with: ".")
    }

    private var userForSubmission: AuthUser {
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

    private func resolveEditingOrderItemStatusID(for item: HomeComposerItemDraft) -> Int? {
        if let existingItem = resolveEditingOrderItem(for: item) {
            return editingItemStatusIDs[existingItem.id] ?? existingItem.orderItemStatusID
        }

        return item.statusID
    }

    private func resolveEditingOrderItem(for item: HomeComposerItemDraft) -> HomeOrderItem? {
        guard let editingOrder else {
            return nil
        }

        return editingOrder.items.first(where: {
            $0.orderItemProductID == item.productID
                && $0.orderItemName == item.name
                && ($0.orderItemArticle ?? "") == item.article
        })
    }

    private func syncSelectedOrderSubMethod() {
        let subMethods = availableOrderSubMethods
        guard !subMethods.isEmpty else {
            selectedOrderSubMethod = nil
            return
        }
        if let selectedOrderSubMethod, subMethods.contains(selectedOrderSubMethod) {
            return
        }
        selectedOrderSubMethod = nil
    }
}
