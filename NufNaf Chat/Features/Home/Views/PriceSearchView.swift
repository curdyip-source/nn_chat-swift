import SwiftUI

/// Экран «Прайс»: поиск по всем прайс-листам (CL + поставщики) с ценой из каждого.
/// Два режима механики (переключаются в настройке): «Широкий» — нечёткий поиск nn_vla
/// по близости; «Точный» — как при создании заказа (каждый токен запроса есть в
/// наименовании). Оба ищут по всем выбранным прайс-листам.
struct PriceSearchView: View {
    @EnvironmentObject private var session: AppSession
    private let client = HomeAPIClient()

    enum SearchMode: String, CaseIterable {
        case wide     // широкий (nn_vla по близости)
        case strict   // точный (все токены запроса)
    }

    private struct DisplayRow: Identifiable {
        let id: String
        let name: String
        let code: String?
        let price: String?
        let sourceLabel: String
        let accented: Bool
    }

    @State private var query = ""
    @State private var rows: [DisplayRow] = []
    @State private var isSearching = false
    @State private var suppliers: [PriceSupplier] = []
    @State private var selectedSources: Set<String> = []
    @State private var mode: SearchMode = .wide
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
            Text(didSearch ? "Ничего не найдено" : "Поиск по всем прайс-листам с ценой")
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
                        Text("Широкий").tag(SearchMode.wide)
                        Text("Точный").tag(SearchMode.strict)
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
            }
            .navigationTitle("Настройки поиска")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(allSelected ? "Снять все" : "Выбрать все") {
                        selectedSources = allSelected ? [] : Set(allSources)
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
        guard !selectedSources.isEmpty else {
            rows = []
            didSearch = true
            return
        }
        isSearching = true
        defer { isSearching = false }
        let emails = allSelected ? [] : Array(selectedSources)
        do {
            let res = try await client.priceSearch(accessToken: token, query: q, emails: emails, strict: mode == .strict)
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
            didSearch = true
        } catch {
            if Task.isCancelled { return }
            rows = []
            didSearch = true
        }
    }
}
