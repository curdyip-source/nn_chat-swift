import SwiftUI
import UIKit

/// Экран создания накладной СДЭК для заказа: получатель → поиск города → способ →
/// поиск ПВЗ по адресу / адрес → габариты → тариф → доп. услуги → создать.
struct CdekWaybillSheet: View {
    let order: HomeOrder
    let store: HomeStore
    let accessToken: String?
    var onCreated: (HomeOrderCdek) -> Void

    @Environment(\.dismiss) private var dismiss

    // Предзаполнение из данных заказа (сохранённых при создании / прошлой накладной).
    @State private var recipientName: String
    @State private var recipientPhone: String
    // Город отправителя (origin). Дефолт — Москва (44); меняем на Тулу и др. при необходимости.
    @State private var fromCityQuery = "Москва"
    @State private var fromCityCode: Int? = 44
    @State private var fromCityResults: [CdekCity] = []
    @State private var suppressFromCitySearch = false
    // ПВЗ сдачи отправителем (origin ПВЗ). Пусто = курьер/договор; выбран = shipment_point.
    @State private var shipmentQuery = ""
    @State private var shipmentPoint: String?
    @State private var shipmentResults: [CdekPvz] = []
    @State private var suppressShipmentSearch = false
    @State private var loadedDefaults = false
    @State private var cityQuery: String
    @State private var cityCode: Int?
    @State private var cityResults: [CdekCity] = []
    @State private var mode: String            // "pvz" | "door"
    @State private var pvzQuery: String
    @State private var pvzCode: String?
    @State private var pvzResults: [CdekPvz] = []
    @State private var deliveryAddress: String

    @State private var weight = "500"
    @State private var length = "20"
    @State private var width = "15"
    @State private var height = "10"

    @State private var tariffs: [CdekTariff] = []
    @State private var loadedTariffKey: String?
    @State private var tariffCode: Int?

    @State private var declaredValue = "0"
    @State private var insurance = false
    @State private var sms = false
    @State private var codAmount = "0"
    @State private var payer = "sender"        // "sender" | "recipient"
    @State private var comment = ""

    @State private var submitting = false
    @State private var errorMessage: String?
    // true, когда текст поля поменяли программно (подстановка выбора), а не вводом —
    // чтобы onChange не сбрасывал выбранный код города/ПВЗ и не запускал поиск.
    @State private var suppressCitySearch = false
    @State private var suppressPvzSearch = false
    @State private var numBuffers: [FocusField: String] = [:]   // очистить при фокусе, вернуть если не меняли
    @FocusState private var focusedField: FocusField?
    private enum FocusField: Hashable { case fromCity, shipment, city, pvz, weight, length, width, height, declared, cod }

    init(order: HomeOrder, store: HomeStore, accessToken: String?, onCreated: @escaping (HomeOrderCdek) -> Void) {
        self.order = order
        self.store = store
        self.accessToken = accessToken
        self.onCreated = onCreated
        let c = order.cdek
        _recipientName = State(initialValue: c?.recipientName ?? order.orderCustomer)
        _recipientPhone = State(initialValue: c?.recipientPhone ?? "")
        _cityQuery = State(initialValue: c?.cityName ?? "")
        _cityCode = State(initialValue: c?.cityCode)
        _mode = State(initialValue: c?.deliveryMode == "door" ? "door" : "pvz")
        _pvzQuery = State(initialValue: c?.pvzAddress ?? "")
        _pvzCode = State(initialValue: c?.pvzCode)
        _deliveryAddress = State(initialValue: c?.deliveryAddress ?? "")
    }

    private var selectedTariff: CdekTariff? { tariffs.first { $0.tariffCode == tariffCode } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section("Получатель") {
                    textFieldRow("ФИО", $recipientName, placeholder: "Иван Иванов")
                    textFieldRow("Телефон", $recipientPhone, placeholder: "+7 900 000-00-00", keyboard: .phonePad)
                }

                Section("Откуда — город отправителя (по умолчанию Москва)") {
                    TextField("Город отправителя", text: $fromCityQuery)
                        .focused($focusedField, equals: .fromCity)
                        .id("fromCityField")
                        .onChange(of: fromCityQuery) { _, q in searchFromCity(q) }
                    ForEach(fromCityResults) { city in
                        Button {
                            suppressFromCitySearch = true
                            fromCityQuery = city.fullName ?? ""
                            fromCityCode = city.code
                            fromCityResults = []
                            clearShipment()
                            hideKeyboard()
                        } label: { Text(city.fullName ?? "—").font(.subheadline) }
                    }

                    TextField(fromCityCode == nil ? "Сначала выберите город" : "ПВЗ отправителя (сдаю в ПВЗ; пусто = курьер)", text: $shipmentQuery)
                        .focused($focusedField, equals: .shipment)
                        .id("shipmentField")
                        .onChange(of: shipmentQuery) { _, q in searchShipment(q) }
                    ForEach(shipmentResults) { p in
                        Button {
                            suppressShipmentSearch = true
                            shipmentQuery = p.address ?? ""
                            shipmentPoint = p.code
                            shipmentResults = []
                            hideKeyboard()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.address ?? "—").font(.subheadline)
                                if let wt = p.workTime, !wt.isEmpty { Text(wt).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }

                Section("Куда — город получателя") {
                    TextField("Поиск по названию", text: $cityQuery)
                        .focused($focusedField, equals: .city)
                        .id("cityField")
                        .onChange(of: cityQuery) { _, q in searchCity(q) }
                    ForEach(cityResults) { city in
                        Button {
                            suppressCitySearch = true
                            cityQuery = city.fullName ?? ""
                            cityCode = city.code
                            cityResults = []
                            hideKeyboard()
                        } label: { Text(city.fullName ?? "—").font(.subheadline) }
                    }
                }

                Section("Доставка") {
                    Picker("Способ", selection: $mode) {
                        Text("В пункт выдачи").tag("pvz")
                        Text("Курьером").tag("door")
                    }.pickerStyle(.segmented)

                    if mode == "pvz" {
                        TextField(cityCode == nil ? "Сначала выберите город" : "Поиск ПВЗ по адресу", text: $pvzQuery)
                            .focused($focusedField, equals: .pvz)
                            .id("pvzField")
                            .onChange(of: pvzQuery) { _, q in searchPvz(q) }
                        ForEach(pvzResults) { p in
                            Button {
                                suppressPvzSearch = true
                                pvzQuery = p.address ?? ""
                                pvzCode = p.code
                                pvzResults = []
                                hideKeyboard()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.address ?? "—").font(.subheadline)
                                    if let wt = p.workTime, !wt.isEmpty { Text(wt).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    } else {
                        TextField("Адрес доставки", text: $deliveryAddress)
                    }
                }

                Section("Габариты посылки") {
                    numberField("Вес, г", $weight, .weight)
                    numberField("Длина, см", $length, .length)
                    numberField("Ширина, см", $width, .width)
                    numberField("Высота, см", $height, .height)
                }

                Section("Тариф") {
                    if cityCode == nil {
                        Text("Сначала выберите город").foregroundStyle(.secondary)
                    } else if tariffs.isEmpty {
                        Text("Загрузка тарифов…").foregroundStyle(.secondary)
                    } else {
                        ForEach(tariffs) { t in
                            Button {
                                tariffCode = t.tariffCode
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.tariffName ?? "Тариф").foregroundStyle(.primary)
                                        Text("\(Int(t.deliverySum ?? 0))₽ · \(t.periodMin ?? 0)–\(t.periodMax ?? 0) дн")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if tariffCode == t.tariffCode {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }

                Section("Доп. услуги") {
                    numberField("Объявленная стоимость, ₽", $declaredValue, .declared)
                    Toggle("Страхование (по объявл. стоимости)", isOn: $insurance)
                    Toggle("СМС-уведомление (зависит от тарифа)", isOn: $sms)
                    numberField("Наложенный платёж, ₽", $codAmount, .cod)
                    Picker("Оплата доставки", selection: $payer) {
                        Text("Отправитель").tag("sender")
                        Text("Получатель").tag("recipient")
                    }
                    TextField("Комментарий (необязательно)", text: $comment)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.subheadline) }
                }
            }
            .scrollDismissesKeyboard(.never)
            .background(KeyboardDismissTap())
            .navigationTitle("Накладная СДЭК")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) { Button(submitting ? "Создание…" : "Создать") { submit() }.disabled(submitting) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { hideKeyboard() }
                }
            }
            .task(id: "\(fromCityCode ?? 0)-\(cityCode ?? 0)-\(weight)") { await loadTariffs() }
            .task { await loadOriginDefault() }
            .onChange(of: focusedField) { _, field in
                guard let field, field == .fromCity || field == .shipment || field == .city || field == .pvz else { return }
                // Поднимаем поле к верху, чтобы результаты поиска были видны над клавиатурой.
                let anchor: String
                switch field {
                case .fromCity: anchor = "fromCityField"
                case .shipment: anchor = "shipmentField"
                case .city: anchor = "cityField"
                default: anchor = "pvzField"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func textFieldRow(_ title: String, _ text: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).keyboardType(keyboard)
        }
    }

    private func numberField(_ title: String, _ text: Binding<String>, _ focus: FocusField) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 96)
                .focused($focusedField, equals: focus)
                .onChange(of: focusedField) { old, new in
                    if old == focus, text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        text.wrappedValue = numBuffers[focus] ?? text.wrappedValue   // не меняли — вернуть
                    }
                    if new == focus {
                        numBuffers[focus] = text.wrappedValue
                        text.wrappedValue = ""
                    }
                }
        }
    }

    private func searchCity(_ query: String) {
        if suppressCitySearch { suppressCitySearch = false; return }
        cityCode = nil
        pvzCode = nil
        pvzQuery = ""
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard cityQuery == query else { return }
            let res = await store.searchCdekCities(accessToken: accessToken, query: query)
            guard cityQuery == query else { return }
            cityResults = res
        }
    }

    private func searchFromCity(_ query: String) {
        if suppressFromCitySearch { suppressFromCitySearch = false; return }
        fromCityCode = nil
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard fromCityQuery == query else { return }
            let res = await store.searchCdekCities(accessToken: accessToken, query: query)
            guard fromCityQuery == query else { return }
            fromCityResults = res
        }
    }

    private func clearShipment() {
        suppressShipmentSearch = true
        shipmentQuery = ""
        shipmentPoint = nil
        shipmentResults = []
    }

    private func searchShipment(_ query: String) {
        if suppressShipmentSearch { suppressShipmentSearch = false; return }
        shipmentPoint = nil
        guard let fromCityCode else { shipmentResults = []; return }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard shipmentQuery == query else { return }
            let res = await store.fetchCdekDeliveryPoints(accessToken: accessToken, cityCode: fromCityCode, query: query)
            guard shipmentQuery == query else { return }
            shipmentResults = res
        }
    }

    private func searchPvz(_ query: String) {
        if suppressPvzSearch { suppressPvzSearch = false; return }
        pvzCode = nil
        guard let cityCode else { pvzResults = []; return }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard pvzQuery == query else { return }
            let res = await store.fetchCdekDeliveryPoints(accessToken: accessToken, cityCode: cityCode, query: query)
            guard pvzQuery == query else { return }
            pvzResults = res
        }
    }

    private func loadOriginDefault() async {
        guard !loadedDefaults else { return }
        loadedDefaults = true
        guard let def = await store.cdekDefaults(accessToken: accessToken), let sp = def.shipmentPoint, !sp.isEmpty else { return }
        if let code = def.fromCityCode {
            suppressFromCitySearch = true
            fromCityQuery = def.fromCityName ?? fromCityQuery
            fromCityCode = code
        }
        suppressShipmentSearch = true
        shipmentQuery = def.shipmentPointAddress ?? ""
        shipmentPoint = sp
    }

    private func loadTariffs() async {
        guard let cityCode else { tariffs = []; tariffCode = nil; loadedTariffKey = nil; return }
        let key = "\(fromCityCode ?? 0)-\(cityCode)-\(Int(weight) ?? 500)"
        guard loadedTariffKey != key else { return }   // уже загружено для этого origin+города+веса
        let res = await store.fetchCdekTariffs(accessToken: accessToken, toCode: cityCode, weight: Int(weight) ?? 500, fromCode: fromCityCode)
        tariffs = res
        loadedTariffKey = key
    }

    private func submit() {
        guard let cityCode else { errorMessage = "Выберите город"; return }
        if mode == "pvz", pvzCode == nil { errorMessage = "Выберите пункт выдачи"; return }
        if mode == "door", deliveryAddress.trimmingCharacters(in: .whitespaces).isEmpty { errorMessage = "Укажите адрес доставки"; return }
        guard let tariffCode else { errorMessage = "Выберите тариф"; return }
        guard !recipientName.trimmingCharacters(in: .whitespaces).isEmpty, !recipientPhone.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Укажите ФИО и телефон получателя"; return
        }
        submitting = true
        errorMessage = nil
        let request = CdekWaybillCreateRequest(
            tariffCode: tariffCode,
            recipientName: recipientName.trimmingCharacters(in: .whitespaces),
            recipientPhone: recipientPhone.trimmingCharacters(in: .whitespaces),
            fromCityCode: fromCityCode,
            fromCityName: fromCityQuery.isEmpty ? nil : fromCityQuery,
            shipmentPoint: shipmentPoint,
            shipmentPointAddress: shipmentPoint != nil ? (shipmentQuery.isEmpty ? nil : shipmentQuery) : nil,
            cityCode: cityCode,
            cityName: cityQuery.isEmpty ? nil : cityQuery,
            deliveryMode: mode,
            pvzCode: mode == "pvz" ? pvzCode : nil,
            pvzAddress: mode == "pvz" ? (pvzQuery.isEmpty ? nil : pvzQuery) : nil,
            deliveryAddress: mode == "door" ? deliveryAddress.trimmingCharacters(in: .whitespaces) : nil,
            package: CdekPackageRequest(weight: Int(weight) ?? 500, length: Int(length) ?? 20, width: Int(width) ?? 15, height: Int(height) ?? 10),
            comment: comment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : comment.trimmingCharacters(in: .whitespaces),
            declaredValue: Double(declaredValue) ?? 0,
            insurance: insurance,
            sms: sms,
            codAmount: Double(codAmount) ?? 0,
            deliveryPaidByRecipient: payer == "recipient",
            deliveryCost: payer == "recipient" ? (selectedTariff?.deliverySum ?? 0) : 0
        )
        Task {
            do {
                let result = try await store.createCdekWaybill(accessToken: accessToken, orderID: order.id, request: request)
                onCreated(result)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                submitting = false
            }
        }
    }
}

/// Закрывает клавиатуру по тапу в любом месте — оконный жест с cancelsTouchesInView=false
/// и делегатом, который игнорирует тапы по полям ввода (поле фокусируется нормально, а
/// тап по кнопке/выбору и закрывает клавиатуру, и срабатывает). Переиспользуется в композере.
struct KeyboardDismissTap: UIViewRepresentable {
    /// Что делать по тапу вне поля. По умолчанию — глобальный resignFirstResponder.
    /// Экраны с @FocusState передают сюда обнуление своего focusedField, иначе
    /// глобальный resign может погасить не то поле (напр. поле чата под sheet).
    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        if context.coordinator.window == nil {
            DispatchQueue.main.async { context.coordinator.attach(to: uiView.window) }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var window: UIWindow?
        var onTap: (() -> Void)?
        private var tap: UITapGestureRecognizer?

        init(onTap: (() -> Void)?) { self.onTap = onTap }

        func attach(to window: UIWindow?) {
            guard let window, self.window == nil else { return }
            let g = UITapGestureRecognizer(target: self, action: #selector(handle))
            g.cancelsTouchesInView = false
            g.delegate = self
            window.addGestureRecognizer(g)
            tap = g
            self.window = window
        }

        func detach() {
            if let tap, let window { window.removeGestureRecognizer(tap) }
            tap = nil
            window = nil
        }

        @objc private func handle() {
            if let onTap {
                onTap()
            } else {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }

        // Не перехватываем тап, если он по полю ввода (иначе поле не сфокусируется).
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}
