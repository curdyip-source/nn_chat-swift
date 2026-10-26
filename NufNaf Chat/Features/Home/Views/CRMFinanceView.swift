import SwiftUI

/// Вкладка «Финансы» в СРМ приложения — упрощённый вариант веб-раздела, чтобы
/// закупку вносили прямо с телефона:
/// - сверху выручка и прибыль за период (в валюте продажи, по валютам);
/// - строка фильтра: отдельные списки день / месяц / год (по умолчанию — сегодня;
///   «Весь месяц» / «Весь год» — смотреть период целиком), «скрыть зафиксированные»;
/// - список отгруженных позиций (дата отгрузки = переход в «Отгружено»): цена
///   продажи (только чтение) и закупочная цена (ввод), фиксатор справа.
/// Закрыта только зафиксированная позиция: без замка она «в работе» и горит красным
/// (даже с внесённой закупкой). Период горит зелёным, когда закрыты все его позиции.
struct CRMFinanceView: View {
    @EnvironmentObject private var session: AppSession
    private let client = HomeAPIClient()

    // Выбор периода: год обязателен; месяц nil — весь год; день nil — весь месяц.
    @State private var year: Int
    @State private var month: Int?
    @State private var day: Int?

    init() {
        let now = Self.calendar.dateComponents([.year, .month, .day], from: Date())
        _year = State(initialValue: now.year ?? 2026)
        _month = State(initialValue: now.month)
        _day = State(initialValue: now.day)
    }
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
                                dateColor: itemColor(item),
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
            // День — только когда выбран месяц; «Весь месяц» — сброс дня.
            Menu {
                Button("Весь месяц") { day = nil }
                Divider()
                ForEach(availableDays.reversed(), id: \.self) { value in
                    Button(dayMenuTitle(value)) { day = value }
                }
            } label: {
                filterPill(day.map { String(format: "%02d", $0) } ?? "Все дни", isFinest: day != nil)
            }
            .disabled(month == nil)
            .opacity(month == nil ? 0.4 : 1)

            Menu {
                Button("Весь год") { month = nil; day = nil }
                Divider()
                ForEach(availableMonths.reversed(), id: \.self) { value in
                    Button(Self.monthNames[value - 1]) {
                        month = value
                        // День, которого нет в новом месяце (31 → февраль) или ещё не наступил, — на последний доступный.
                        if let current = day, !availableDays(year: year, month: value).contains(current) {
                            day = availableDays(year: year, month: value).last
                        }
                    }
                }
            } label: {
                filterPill(month.map { Self.monthNames[$0 - 1] } ?? "Все месяцы", isFinest: month != nil && day == nil)
            }

            Menu {
                ForEach(availableYears.reversed(), id: \.self) { value in
                    Button(String(value)) {
                        year = value
                        if let current = month, !availableMonths(year: value).contains(current) {
                            month = availableMonths(year: value).last
                        }
                        if let m = month, let current = day, !availableDays(year: value, month: m).contains(current) {
                            day = availableDays(year: value, month: m).last
                        }
                    }
                }
            } label: {
                filterPill(String(year), isFinest: month == nil)
            }

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

    /// Кнопка-список фильтра. Самая «мелкая» выбранная часть (день, иначе месяц,
    /// иначе год) подсвечена цветом готовности периода: зелёный — всё внесено.
    private func filterPill(_ title: String, isFinest: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isFinest ? periodColor : AppTheme.secondaryButtonText)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.secondaryButtonText.opacity(0.7))
        }
        .padding(.horizontal, 11)
        // Списки делят ширину строки поровну — фильтр на всю ширину экрана.
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(AppTheme.secondaryButtonBackground, in: Capsule())
    }

    // MARK: - Период

    private static let monthNames = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE"
        return formatter
    }()

    private var today: DateComponents {
        Self.calendar.dateComponents([.year, .month, .day], from: Date())
    }

    /// Годы — с 2025 (раньше отгрузок в системе нет) по текущий.
    private var availableYears: [Int] {
        Array(2025...max(today.year ?? year, year))
    }

    private var availableMonths: [Int] { availableMonths(year: year) }

    private func availableMonths(year: Int) -> [Int] {
        // Будущие месяцы не показываем.
        let last = year == today.year ? (today.month ?? 12) : 12
        return Array(1...last)
    }

    private var availableDays: [Int] {
        guard let month else { return [] }
        return availableDays(year: year, month: month)
    }

    private func availableDays(year: Int, month: Int) -> [Int] {
        guard let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = Self.calendar.range(of: .day, in: .month, for: start) else { return [] }
        // Будущие дни не показываем.
        let last = (year == today.year && month == today.month) ? (today.day ?? range.count) : range.count
        return Array(1...max(last, 1))
    }

    /// «26 · пн · сегодня» — чтобы вчера/сегодня находились сразу.
    private func dayMenuTitle(_ value: Int) -> String {
        guard let month, let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: value)) else {
            return String(value)
        }
        var title = "\(value) · \(Self.weekdayFormatter.string(from: date))"
        if year == today.year, month == today.month {
            if value == today.day { title += " · сегодня" }
            if let todayDay = today.day, value == todayDay - 1 { title += " · вчера" }
        }
        return title
    }

    private var interval: (from: Date, to: Date) {
        let calendar = Self.calendar
        let startComponents = DateComponents(year: year, month: month ?? 1, day: day ?? 1)
        let start = calendar.date(from: startComponents) ?? Date()
        let component: Calendar.Component = day != nil ? .day : (month != nil ? .month : .year)
        let next = calendar.date(byAdding: component, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: next) ?? start
        return (start, end)
    }

    /// Ключ перезагрузки — сам выбранный период.
    private var periodKey: String {
        "\(year)-\(month ?? 0)-\(day ?? 0)"
    }

    // MARK: - Цвета дней

    private static let completeColor = Color(red: 0.30, green: 0.82, blue: 0.48)
    private static let incompleteColor = Color(red: 0.95, green: 0.55, blue: 0.55)

    /// Период закрыт, когда все его позиции зафиксированы.
    private var periodColor: Color {
        guard let items = data?.items, !items.isEmpty else { return AppTheme.secondaryButtonText }
        return items.allSatisfy(\.locked) ? Self.completeColor : Self.incompleteColor
    }

    /// Позиция: зафиксирована — зелёная, в работе (без замка) — красная.
    private func itemColor(_ item: AppFinanceItem) -> Color {
        item.locked ? Color(red: 0.12, green: 0.58, blue: 0.30) : Color(red: 0.86, green: 0.36, blue: 0.36)
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
        // В работе (не зафиксирована) — бледно-красная рамка.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(item.locked ? Color.clear : Color(red: 0.95, green: 0.55, blue: 0.55), lineWidth: 2)
        )
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
