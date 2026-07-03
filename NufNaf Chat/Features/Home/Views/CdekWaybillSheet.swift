import SwiftUI

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
            Form {
                Section("Получатель") {
                    TextField("ФИО", text: $recipientName)
                    TextField("Телефон", text: $recipientPhone).keyboardType(.phonePad)
                }

                Section("Город") {
                    TextField("Поиск по названию", text: $cityQuery)
                        .onChange(of: cityQuery) { _, q in searchCity(q) }
                    ForEach(cityResults) { city in
                        Button {
                            suppressCitySearch = true
                            cityQuery = city.fullName ?? ""
                            cityCode = city.code
                            cityResults = []
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
                            .onChange(of: pvzQuery) { _, q in searchPvz(q) }
                        ForEach(pvzResults) { p in
                            Button {
                                suppressPvzSearch = true
                                pvzQuery = p.address ?? ""
                                pvzCode = p.code
                                pvzResults = []
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
                    numberField("Вес, г", $weight)
                    numberField("Длина, см", $length)
                    numberField("Ширина, см", $width)
                    numberField("Высота, см", $height)
                }

                Section("Тариф") {
                    if cityCode == nil {
                        Text("Сначала выберите город").foregroundStyle(.secondary)
                    } else if tariffs.isEmpty {
                        Text("Загрузка тарифов…").foregroundStyle(.secondary)
                    } else {
                        Picker("Тариф", selection: Binding(get: { tariffCode ?? -1 }, set: { tariffCode = $0 == -1 ? nil : $0 })) {
                            Text("— выберите —").tag(-1)
                            ForEach(tariffs) { t in
                                Text("\(t.tariffName ?? "Тариф") — \(Int(t.deliverySum ?? 0))₽ (\(t.periodMin ?? 0)–\(t.periodMax ?? 0) дн)").tag(t.tariffCode)
                            }
                        }
                    }
                }

                Section("Доп. услуги") {
                    numberField("Объявленная стоимость, ₽", $declaredValue)
                    Toggle("Страхование (по объявл. стоимости)", isOn: $insurance)
                    Toggle("СМС-уведомление (зависит от тарифа)", isOn: $sms)
                    numberField("Наложенный платёж, ₽", $codAmount)
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
            .navigationTitle("Накладная СДЭК")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) { Button(submitting ? "Создание…" : "Создать") { submit() }.disabled(submitting) }
            }
            .task(id: "\(cityCode ?? 0)-\(weight)") { await loadTariffs() }
        }
    }

    private func numberField(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
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

    private func loadTariffs() async {
        guard let cityCode else { tariffs = []; tariffCode = nil; return }
        let res = await store.fetchCdekTariffs(accessToken: accessToken, toCode: cityCode, weight: Int(weight) ?? 500)
        tariffs = res
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
