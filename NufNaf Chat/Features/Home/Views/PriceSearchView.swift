import SwiftUI

/// Экран «Прайс»: живой поиск по всем прайс-листам (CL + поставщики) с ценой,
/// плюс настройка «в каких прайс-листах искать». Данные — через chat-прокси в nn_vla.
struct PriceSearchView: View {
    @EnvironmentObject private var session: AppSession
    private let client = HomeAPIClient()

    @State private var query = ""
    @State private var results: [PriceSearchResult] = []
    @State private var isSearching = false
    @State private var suppliers: [PriceSupplier] = []
    @State private var selectedSources: Set<String> = []
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
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text(sourcesSummary)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var sourcesSummary: String {
        if allSources.isEmpty { return "Источники" }
        if allSelected { return "Все прайсы" }
        return "\(selectedSources.count)/\(allSources.count)"
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
            TextField("Артикул или название", text: $query)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    didSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            if isSearching {
                ProgressView().tint(.white).controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onChange(of: query) { _, _ in scheduleSearch() }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if isSearching && results.isEmpty {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if results.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results, id: \.rowID) { resultRow($0) }
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

    private func resultRow(_ row: PriceSearchResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(sourceLabel(row))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(row.isCL ? Color(red: 0.48, green: 0.84, blue: 0.60) : .white.opacity(0.55))
                    if let code = row.code, !code.isEmpty {
                        Text("· \(code)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            Spacer(minLength: 8)
            Text(priceText(row.price))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func sourceLabel(_ row: PriceSearchResult) -> String {
        row.isCL ? "CL · мой прайс" : (row.supplier ?? row.source)
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
        // В прайс-данных валюты нет — показываем просто число (группировка разрядов),
        // без значка валюты.
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
                } footer: {
                    Text("Отмечены все — поиск по всем. Поставщики со свежими прайсами обновляются автоматически.")
                }
            }
            .navigationTitle("Источники")
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
            selectedSources = Set(["CL"] + list.map(\.email)) // по умолчанию — все
        } catch {
            suppliers = []
            selectedSources = ["CL"]
        }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
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
        // Пустой выбор источников — показываем пусто, в сеть не ходим.
        guard !selectedSources.isEmpty else {
            results = []
            didSearch = true
            return
        }
        isSearching = true
        defer { isSearching = false }
        let emails = allSelected ? [] : Array(selectedSources)
        do {
            let res = try await client.priceSearch(accessToken: token, query: q, emails: emails)
            if Task.isCancelled { return }
            results = res
            didSearch = true
        } catch {
            if Task.isCancelled { return }
            results = []
            didSearch = true
        }
    }
}
