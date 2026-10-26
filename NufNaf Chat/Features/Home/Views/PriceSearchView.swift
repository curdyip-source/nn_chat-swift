import SwiftUI

/// Экран «Прайс»: поиск цены товара. В настройках переключатель — где искать:
/// - «Поиск по прайсам» — по всем прайс-листам (CL + поставщики). Два режима механики:
///   «Точный» (по умолчанию; как при создании заказа — каждый токен запроса есть в
///   наименовании) и «Широкий» — нечёткий поиск nn_vla по близости;
/// - «Поиск по приемкам» — по нашим приёмкам, отбор как у точного поиска, цена —
///   последняя / средняя за всё время / средняя за 3 месяца.
struct PriceSearchView: View {
    @EnvironmentObject private var session: AppSession
    private let client = HomeAPIClient()

    enum SearchMode: String, CaseIterable {
        case wide     // широкий (nn_vla по близости)
        case strict   // точный (все токены запроса)
    }

    /// Где искать — либо прайс-листы, либо наши приёмки.
    enum SearchSource: String, CaseIterable {
        case prices
        case registrations
    }

    /// Какую цену брать из приёмок.
    enum RegistrationPriceMode: String, CaseIterable {
        case last = "last"
        case averageAll = "avg_all"
        case averageThreeMonths = "avg_3m"

        var title: String {
            switch self {
            case .last: return "Последняя приемка"
            case .averageAll: return "Средняя за всё время"
            case .averageThreeMonths: return "Средняя за 3 месяца"
            }
        }
    }

    private enum RowAccent {
        case none
        case myPrice       // CL — зелёный
        case registration  // приёмка — синий
    }

    private struct DisplayRow: Identifiable {
        let id: String
        let name: String
        let code: String?
        let price: String?
        /// Знак валюты после цены — только для приёмок не в USD (прайсы все в USD).
        var currency: String? = nil
        let sourceLabel: String
        let accent: RowAccent
    }

    @State private var query = ""
    @State private var rows: [DisplayRow] = []
    @State private var isSearching = false
    @State private var suppliers: [PriceSupplier] = []
    @State private var selectedSources: Set<String> = []
    @State private var mode: SearchMode = .strict
    @State private var source: SearchSource = .prices
    @State private var registrationPriceMode: RegistrationPriceMode = .last
    @State private var showSettings = false
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?

    private var allSources: [String] { ["CL"] + suppliers.map(\.email) }
    private var allSelected: Bool { !allSources.isEmpty && selectedSources.count == allSources.count }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .task { await loadSuppliers() }
        .sheet(isPresented: $showSettings, onDismiss: { scheduleSearch(immediate: true) }) { settingsSheet }
    }

    // MARK: - Search bar (стиль как в СРМ-поиске; значок настройки внутри поля)

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))

            TextField(
                "",
                text: $query,
                prompt: Text("Артикул или название").foregroundStyle(Color.white.opacity(0.82))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .tint(.white)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if isSearching {
                ProgressView().tint(.white).controlSize(.small)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    rows = []
                    didSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .buttonStyle(.plain)
            }

            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.82), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
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
            Text(didSearch ? "Ничего не найдено" : idleHint)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private var idleHint: String {
        switch source {
        case .prices: return "Поиск по всем прайс-листам с ценой"
        case .registrations: return "Поиск по приемкам с ценой"
        }
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
                        .foregroundStyle(accentColor(row.accent))
                    if let code = row.code, !code.isEmpty {
                        Text("· \(code)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
            }
            Spacer(minLength: 8)
            Text([priceText(row.price), row.currency].compactMap { $0 }.joined(separator: " "))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func accentColor(_ accent: RowAccent) -> Color {
        switch accent {
        case .none: return .black.opacity(0.5)
        case .myPrice: return Color(red: 0.09, green: 0.52, blue: 0.30)
        case .registration: return Color(red: 0.16, green: 0.38, blue: 0.82)
        }
    }

    private func priceText(_ price: String?) -> String {
        guard let price, !price.isEmpty else { return "—" }
        if let value = Decimal(string: price) {
            // Единый формат сумм приложения: разряды тысяч через пробел.
            return AppAmount.grouped(value)
        }
        return AppAmount.grouped(price)
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Где искать", selection: $source) {
                        Text("Поиск по прайсам").tag(SearchSource.prices)
                        Text("Поиск по приемкам").tag(SearchSource.registrations)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if source == .prices {
                    Section {
                        Picker("Режим", selection: $mode) {
                            Text("Точный").tag(SearchMode.strict)
                            Text("Широкий").tag(SearchMode.wide)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Механика поиска")
                    } footer: {
                        Text(mode == .wide
                             ? "Широкий поиск по близости — находит больше похожих позиций."
                             : "Точный — каждое слово запроса должно быть в наименовании (как при создании заказа). Находит меньше и точнее.")
                    }

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
                } else {
                    Section {
                        Picker("Цена", selection: $registrationPriceMode) {
                            ForEach(RegistrationPriceMode.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Какую цену показывать")
                    } footer: {
                        Text("Поиск как точный по прайсам: каждое слово запроса — часть наименования или артикула. Средняя — по всем приемкам товара за период.")
                    }
                }
            }
            .navigationTitle("Настройки поиска")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if source == .prices {
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
        if source == .prices && selectedSources.isEmpty {
            rows = []
            didSearch = true
            return
        }
        isSearching = true
        defer { isSearching = false }

        let result = source == .prices
            ? await searchPrices(q, token: token)
            : await searchRegistrations(q, token: token)
        if Task.isCancelled { return }
        rows = result
        didSearch = true
    }

    private func searchPrices(_ q: String, token: String) async -> [DisplayRow] {
        let emails = allSelected ? [] : Array(selectedSources)
        guard let res = try? await client.priceSearch(accessToken: token, query: q, emails: emails, strict: mode == .strict) else {
            return []
        }
        return res.map { r in
            DisplayRow(
                id: r.rowID,
                name: r.name,
                code: r.code,
                price: r.price,
                sourceLabel: r.isCL ? "CL · мой прайс" : (r.supplier ?? r.source),
                accent: r.isCL ? .myPrice : .none
            )
        }
    }

    private func searchRegistrations(_ q: String, token: String) async -> [DisplayRow] {
        let priceMode = registrationPriceMode
        guard let res = try? await client.registrationPriceSearch(accessToken: token, query: q, mode: priceMode.rawValue) else {
            return []
        }
        return res.map { r in
            // Последняя — номер этой приемки; средняя — по скольким приемкам посчитана.
            let label = priceMode == .last
                ? "Приемка №\(r.registrationID)"
                : "Средняя по \(r.registrationsCount) \(r.registrationsCount == 1 ? "приемке" : "приемкам")"
            return DisplayRow(
                id: "registration-\(r.id)",
                name: r.name,
                code: r.code,
                price: r.price,
                currency: r.isDefaultCurrency ? nil : r.currency,
                sourceLabel: label,
                accent: .registration
            )
        }
    }
}
