import SwiftUI

/// Вкладка «Финансы» в СРМ приложения — упрощённый вариант веб-раздела, чтобы
/// закупку вносили прямо с телефона:
/// - сверху выручка и прибыль за период (в валюте продажи, по валютам);
/// - строка фильтра: день / месяц / год (по умолчанию — текущий), листание
///   периода, «скрыть зафиксированные»;
/// - список отгруженных позиций (дата отгрузки = переход в «Отгружено»): цена
///   продажи (только чтение) и закупочная цена (ввод), фиксатор справа.
/// Дата горит зелёным, если закупка внесена у всех позиций этого дня, иначе — бледно-красным.
struct CRMFinanceView: View {
    @EnvironmentObject private var session: AppSession
    private let client = HomeAPIClient()

    enum PeriodKind: String, CaseIterable {
        case day = "День"
        case month = "Месяц"
        case year = "Год"
    }

    @State private var periodKind: PeriodKind = .day
    @State private var anchor = Date()
    @State private var hidesLocked = false
    @State private var data: AppFinanceResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var savingItemIDs: Set<Int> = []

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        // Период на сервере — в UTC-днях (как и фильтр веба), считаем в той же шкале.
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 10) {
            totalsRow
            filterRow

            ScrollView {
                LazyVStack(spacing: 10) {
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.92))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if isLoading && data == nil {
                        ProgressView().tint(.white).padding(.top, 24)
                    } else if visibleItems.isEmpty {
                        Text(emptyTitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(visibleItems) { item in
                            CRMFinanceItemRow(
                                item: item,
                                dateTitle: dayTitle(item.shippedDate),
                                dateColor: dayColor(item.shippedDate),
                                isSaving: savingItemIDs.contains(item.id),
                                onSavePurchase: { value in savePurchase(item: item, value: value) },
                                onToggleLock: { toggleLock(item) }
                            )
                        }
                    }
                }
                .padding(.top, 2)
                // Резерв под закреплённое меню разделов СРМ (оверлей снизу).
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
        }
        .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
        .padding(.top, 8)
        .task(id: periodKey) { await load() }
    }

    // MARK: - Итоги

    private var totalsRow: some View {
        HStack(spacing: 10) {
            totalCard(title: "Выручка", totals: data?.revenue ?? [], caption: nil)
            totalCard(
                title: "Прибыль",
                totals: data?.profit ?? [],
                caption: (data?.missingPurchaseCount ?? 0) > 0 ? "без закупки: \(data?.missingPurchaseCount ?? 0)" : nil
            )
        }
    }

    private func totalCard(title: String, totals: [AppFinanceTotal], caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.5))
            Text(totals.isEmpty ? "—" : totals.map { "\(AppAmount.grouped($0.amount)) \($0.currency)" }.joined(separator: " + "))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.80, green: 0.30, blue: 0.30))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Фильтр

    private var filterRow: some View {
        HStack(spacing: 8) {
            // День / Месяц / Год.
            HStack(spacing: 2) {
                ForEach(PeriodKind.allCases, id: \.self) { kind in
                    Button {
                        periodKind = kind
                        anchor = Date()
                    } label: {
                        Text(kind.rawValue)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(periodKind == kind ? AppTheme.primaryButtonText : AppTheme.secondaryButtonText)
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .background(periodKind == kind ? AppTheme.primaryButtonBackground : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(AppTheme.secondaryButtonBackground, in: Capsule())

            // ‹ период › — цвет: всё внесено / нет.
            HStack(spacing: 2) {
                periodArrow("chevron.left") { shift(by: -1) }
                Text(periodTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(periodColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                periodArrow("chevron.right") { shift(by: 1) }
                    .disabled(isCurrentPeriod)
                    .opacity(isCurrentPeriod ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity)

            // Скрыть зафиксированные.
            Button {
                hidesLocked.toggle()
            } label: {
                Image(systemName: hidesLocked ? "lock.slash.fill" : "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hidesLocked ? AppTheme.primaryButtonText : AppTheme.secondaryButtonText)
                    .frame(width: 34, height: 34)
                    .background(hidesLocked ? AppTheme.primaryButtonBackground : AppTheme.secondaryButtonBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hidesLocked ? "Показать зафиксированные" : "Скрыть зафиксированные")
        }
    }

    private func periodArrow(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.secondaryButtonText)
                .frame(width: 26, height: 30)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Период

    private var interval: (from: Date, to: Date) {
        let calendar = Self.calendar
        let component: Calendar.Component = periodKind == .day ? .day : (periodKind == .month ? .month : .year)
        let start = calendar.dateInterval(of: component, for: anchor)?.start ?? anchor
        let next = calendar.date(byAdding: component, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: next) ?? start
        return (start, end)
    }

    /// Ключ перезагрузки: смена вида периода или самого периода.
    private var periodKey: String {
        "\(periodKind.rawValue)-\(Self.apiDateFormatter.string(from: interval.from))"
    }

    private var isCurrentPeriod: Bool {
        let now = interval
        return Date() >= now.from && Date() < (Self.calendar.date(byAdding: .day, value: 1, to: now.to) ?? now.to)
    }

    private var periodTitle: String {
        switch periodKind {
        case .day: return Self.shortDayFormatter.string(from: interval.from)
        case .month: return Self.monthFormatter.string(from: interval.from).capitalized
        case .year: return String(Self.calendar.component(.year, from: interval.from))
        }
    }

    private func shift(by value: Int) {
        let component: Calendar.Component = periodKind == .day ? .day : (periodKind == .month ? .month : .year)
        anchor = Self.calendar.date(byAdding: component, value: value, to: anchor) ?? anchor
    }

    // MARK: - Цвета дней

    private static let completeColor = Color(red: 0.30, green: 0.82, blue: 0.48)
    private static let incompleteColor = Color(red: 0.95, green: 0.55, blue: 0.55)

    /// День → закупка внесена у всех позиций этого дня (по всем, не только видимым).
    private var dayCompleteness: [String: Bool] {
        var result: [String: Bool] = [:]
        for item in data?.items ?? [] {
            guard let day = item.shippedDate else { continue }
            result[day] = (result[day] ?? true) && item.purchasePrice != nil
        }
        return result
    }

    private var periodColor: Color {
        guard let items = data?.items, !items.isEmpty else { return AppTheme.secondaryButtonText }
        return items.allSatisfy { $0.purchasePrice != nil } ? Self.completeColor : Self.incompleteColor
    }

    private func dayColor(_ day: String?) -> Color {
        guard let day, let complete = dayCompleteness[day] else { return .black.opacity(0.5) }
        // В строке (светлая карточка) — те же оттенки, чуть темнее для читаемости.
        return complete ? Color(red: 0.12, green: 0.58, blue: 0.30) : Color(red: 0.86, green: 0.36, blue: 0.36)
    }

    private func dayTitle(_ day: String?) -> String {
        guard let day, let date = Self.apiDateFormatter.date(from: day) else { return "—" }
        return Self.shortDayFormatter.string(from: date)
    }

    // MARK: - Список

    private var visibleItems: [AppFinanceItem] {
        let items = data?.items ?? []
        return hidesLocked ? items.filter { !$0.locked } : items
    }

    private var emptyTitle: String {
        if hidesLocked, !(data?.items.isEmpty ?? true) {
            return "Все позиции за период зафиксированы"
        }
        return "За этот период отгрузок нет"
    }

    // MARK: - Данные

    private func load() async {
        guard let token = session.currentAccessToken else { return }
        let range = interval
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.appFinance(
                accessToken: token,
                dateFrom: Self.apiDateFormatter.string(from: range.from),
                dateTo: Self.apiDateFormatter.string(from: range.to)
            )
            // Ответ на уже сменённый период не применяем.
            guard range.from == interval.from, range.to == interval.to else { return }
            data = response
            errorMessage = nil
        } catch {
            if Task.isCancelled { return }
            errorMessage = resolveActionError(error)
        }
    }

    private func savePurchase(item: AppFinanceItem, value: String?) {
        guard value != item.purchasePrice else { return }
        guard let token = session.currentAccessToken else { return }
        Task {
            savingItemIDs.insert(item.id)
            defer { savingItemIDs.remove(item.id) }
            do {
                _ = try await client.setAppFinancePurchase(accessToken: token, itemID: item.id, purchasePrice: value)
                // Итоги и цвета дней пересчитывает сервер — перечитываем период.
                await load()
            } catch {
                errorMessage = resolveActionError(error)
            }
        }
    }

    private func toggleLock(_ item: AppFinanceItem) {
        guard let token = session.currentAccessToken else { return }
        Task {
            savingItemIDs.insert(item.id)
            defer { savingItemIDs.remove(item.id) }
            do {
                let updated = try await client.setAppFinanceLock(accessToken: token, itemID: item.id, locked: !item.locked)
                replace(updated)
                errorMessage = nil
            } catch {
                errorMessage = resolveActionError(error)
            }
        }
    }

    private func replace(_ updated: AppFinanceItem) {
        guard let current = data else { return }
        data = AppFinanceResponse(
            revenue: current.revenue,
            profit: current.profit,
            itemsCount: current.itemsCount,
            missingPurchaseCount: current.missingPurchaseCount,
            items: current.items.map { $0.id == updated.id ? updated : $0 }
        )
    }
}

/// Строка отгруженной позиции:
/// «26.10.26 · Заказ №123 · Склад»                    [фиксатор]
/// Наименование
/// [Продажа — только чтение]  [Закупка — ввод, в той же валюте]
private struct CRMFinanceItemRow: View {
    let item: AppFinanceItem
    let dateTitle: String
    let dateColor: Color
    let isSaving: Bool
    let onSavePurchase: (String?) -> Void
    let onToggleLock: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(item: AppFinanceItem, dateTitle: String, dateColor: Color, isSaving: Bool, onSavePurchase: @escaping (String?) -> Void, onToggleLock: @escaping () -> Void) {
        self.item = item
        self.dateTitle = dateTitle
        self.dateColor = dateColor
        self.isSaving = isSaving
        self.onSavePurchase = onSavePurchase
        self.onToggleLock = onToggleLock
        _text = State(initialValue: Self.displayValue(item.purchasePrice))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    Text(dateTitle)
                        .foregroundStyle(dateColor)
                    Text("· Заказ №\(item.orderID)")
                        .foregroundStyle(.black.opacity(0.5))
                    if let establishment = item.establishmentName, !establishment.isEmpty {
                        Text("· \(establishment)")
                            .foregroundStyle(.black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))

                Spacer(minLength: 4)

                if isSaving {
                    ProgressView().controlSize(.mini)
                }

                Button(action: onToggleLock) {
                    Image(systemName: item.locked ? "lock.fill" : "lock.open")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(item.locked ? Color.white : Color.black.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(item.locked ? Color.black : Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving || (!item.locked && item.purchasePrice == nil))
                .opacity(!item.locked && item.purchasePrice == nil ? 0.4 : 1)
                .accessibilityLabel(item.locked ? "Снять фиксацию" : "Зафиксировать")
            }

            Text(item.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                // Продажа — только чтение.
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.quantity > 1 ? "Продажа · \(item.quantity) шт." : "Продажа")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(AppAmount.grouped(item.price)) \(item.currency)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Закупка — ввод, в валюте продажи.
                VStack(alignment: .leading, spacing: 3) {
                    Text("Закупка")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: $text,
                            prompt: Text(item.suggestedPurchasePrice.map { "≈ \(Self.displayValue($0))" } ?? "Цена")
                                .foregroundStyle(Color.black.opacity(0.3))
                        )
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .disabled(item.locked)
                        Text(item.currency)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isFocused ? Color.black.opacity(0.6) : Color.black.opacity(item.purchasePrice == nil && !item.locked ? 0.25 : 0.1), lineWidth: 1)
                )
                .opacity(item.locked ? 0.6 : 1)
                .contentShape(Rectangle())
                .onTapGesture { if !item.locked { isFocused = true } }
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .light)
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { isFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
        // Сохраняем, когда поле теряет фокус (Готово / тап в другое поле / скролл).
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            commit()
        }
        // Сервер вернул новое значение (перечитали период) — подтягиваем, если не печатаем.
        .onChange(of: item.purchasePrice) { _, newValue in
            if !isFocused { text = Self.displayValue(newValue) }
        }
    }

    private func commit() {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            if item.purchasePrice != nil { onSavePurchase(nil) }
            return
        }
        guard let value = Decimal(string: normalized), value >= 0 else {
            text = Self.displayValue(item.purchasePrice)
            return
        }
        let formatted = Self.apiValue(value)
        if formatted != item.purchasePrice {
            onSavePurchase(formatted)
        }
        text = Self.displayValue(formatted)
    }

    /// «12000.00» → «12000», «12.50» → «12.5» — для поля ввода без лишних нулей.
    static func displayValue(_ raw: String?) -> String {
        guard let raw, let value = Decimal(string: raw) else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    /// В формате сервера: две цифры после точки.
    private static func apiValue(_ value: Decimal) -> String {
        var rounded = Decimal()
        var source = value
        NSDecimalRound(&rounded, &source, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "\(rounded)"
    }
}
