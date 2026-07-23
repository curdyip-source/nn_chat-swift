import SwiftUI

/// Экран «Прайс»: поиск по прайс-листам с двумя режимами (переключаются в настройке):
/// «По прайсам» — широкий нечёткий поиск nn_vla по всем прайс-листам (CL + поставщики)
/// с выбором источников; «Точный» — как при создании заказа (узкий токен-поиск по каталогу).
struct PriceSearchView: View {
    @EnvironmentObject private var session: AppSession
    private let client = HomeAPIClient()

    enum SearchMode: String, CaseIterable {
        case priceLists   // как сейчас — по всем прайс-листам (nn_vla search_all)
        case catalog      // как в композере заказа — точный поиск по каталогу
    }

    /// Единая строка результата для обоих режимов.
    private struct DisplayRow: Identifiable {
        let id: String
        let name: String
        let code: String?
        let price: String?
        let sourceLabel: String
        let accented: Bool   // зелёная метка источника (CL/каталог)
    }

    @State private var query = ""
    @State private var rows: [DisplayRow] = []
    @State private var isSearching = false
    @State private var suppliers: [PriceSupplier] = []
    @State private var selectedSources: Set<String> = []
    @State private var mode: SearchMode = .priceLists
    @State private var showSettings = false
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?

    private var allSources: [String] { ["CL"] + suppliers.map(\.email) }
    private var allSelected: Bool { !allSources.isEmpty && selectedSources.count == allSources.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .task { await loadSuppliers() }
        .sheet(isPresented: $showSettings, onDismiss: { scheduleSearch(immediate: true) }) { settingsSheet }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Прайс")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.black.opacity(0.4))
            TextField("Артикул или название", text: $query)
                .foregroundStyle(.black)
                .tint(.black)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                    rows = []
                    didSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.black.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            if isSearching {
                ProgressView().tint(.black).controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onChange(of: query) { _, _ in scheduleSearch() }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if isSearching && rows.isEmpty {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if rows.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { resultRow($0) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: didSearch ? "magnifyingglass" : "tag")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.22))
            Text(didSearch ? "Ничего не найдено" : "Поиск по прайс-листам с ценой")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private func resultRow(_ row: DisplayRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(row.sourceLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(row.accented ? Color(red: 0.09, green: 0.52, blue: 0.30) : .black.opacity(0.5))
                    if let code = row.code, !code.isEmpty {
                        Text("· \(code)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
            }
            Spacer(minLength: 8)
            Text(priceText(row.price))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private func priceText(_ price: String?) -> String {
        guard let price, !price.isEmpty else { return "—" }
        if let value = Decimal(string: price) {
            return Self.priceFormatter.string(from: value as NSDecimalNumber) ?? price
        }
        return price
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Режим", selection: $mode) {
                        Text("По прайсам").tag(SearchMode.priceLists)
                        Text("Точный").tag(SearchMode.catalog)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Режим поиска")
                } footer: {
                    Text(mode == .priceLists
                         ? "Широкий поиск по всем прайс-листам (CL + поставщики), с ценой из каждого."
                         : "Точный поиск по каталогу — как при создании заказа (находит меньше и точнее).")
                }

                if mode == .priceLists {
                    Section {
                        ForEach(allSources, id: \.self) { src in
                            Button {
                                toggleSource(src)
                            } label: {
                                HStack {
                                    Text(src == "CL" ? "CL (мой прайс)" : src)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedSources.contains(src) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color(red: 0.09, green: 0.64, blue: 0.35))
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("В каких прайс-листах искать")
                    }
                }
            }
            .navigationTitle("Настройки поиска")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .priceLists {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(allSelected ? "Снять все" : "Выбрать все") {
                            selectedSources = allSelected ? [] : Set(allSources)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { showSettings = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleSource(_ src: String) {
        if selectedSources.contains(src) {
            selectedSources.remove(src)
        } else {
            selectedSources.insert(src)
        }
    }

    // MARK: - Data

    private func loadSuppliers() async {
        guard let token = session.currentAccessToken else { return }
        do {
            let list = try await client.priceSuppliers(accessToken: token)
            suppliers = list
            selectedSources = Set(["CL"] + list.map(\.email))
        } catch {
            suppliers = []
            selectedSources = ["CL"]
        }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            rows = []
            isSearching = false
            didSearch = false
            return
        }
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
            }
            await runSearch(q)
        }
    }

    @MainActor
    private func runSearch(_ q: String) async {
        guard let token = session.currentAccessToken else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch mode {
            case .priceLists:
                guard !selectedSources.isEmpty else { rows = []; didSearch = true; return }
                let emails = allSelected ? [] : Array(selectedSources)
                let res = try await client.priceSearch(accessToken: token, query: q, emails: emails)
                if Task.isCancelled { return }
                rows = res.map { r in
                    DisplayRow(
                        id: r.rowID,
                        name: r.name,
                        code: r.code,
                        price: r.price,
                        sourceLabel: r.isCL ? "CL · мой прайс" : (r.supplier ?? r.source),
                        accented: r.isCL
                    )
                }
            case .catalog:
                let products = try await client.searchProducts(accessToken: token, query: q)
                if Task.isCancelled { return }
                rows = products.map { p in
                    DisplayRow(
                        id: "cat-\(p.id)",
                        name: p.productName,
                        code: p.productArticle,
                        price: p.productCostUSD,
                        sourceLabel: "Каталог",
                        accented: true
                    )
                }
            }
            didSearch = true
        } catch {
            if Task.isCancelled { return }
            rows = []
            didSearch = true
        }
    }
}
