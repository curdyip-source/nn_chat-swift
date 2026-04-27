import SwiftUI

struct CRMDocumentsListView: View {
    let messages: [HomeMessage]
    let referenceData: HomeReferenceDataResponse
    let isLoading: Bool
    let errorMessage: String?
    let updatingDocumentKey: String?
    let onOpenDocument: (String, Int) -> Void
    let onSelectOrderStatus: (HomeOrder, Int) -> Void
    let onSelectOrderItemStatus: (HomeOrder, Int, Int, Int?, Int?) -> Void
    let onSelectInventoryStatus: (HomeInventory, Int) -> Void
    let onSelectProductRegistrationStatus: (HomeProductRegistration, Int) -> Void

    @State private var movementSelection: CRMMovementSelection?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.92))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if isLoading && messages.isEmpty {
                        Text("Загружаем CRM...")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if messages.isEmpty {
                        Text("По текущему фильтру документы не найдены")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } else {
                        ForEach(messages) { message in
                            if let order = message.order {
                                CRMOrderCardView(
                                    order: order,
                                    orderMethods: referenceData.orderMethods,
                                    itemStatuses: orderItemStatuses,
                                    statuses: referenceData.statuses.filter { $0.statusType == "orders" },
                                    currencyTitleProvider: currencyTitle(for:),
                                    isSaving: updatingDocumentKey == documentKey(kind: "order", id: order.id),
                                    onOpen: {
                                        onOpenDocument("order", order.id)
                                    },
                                    onSelectStatus: { statusID in
                                        onSelectOrderStatus(order, statusID)
                                    },
                                    onSelectItemStatus: { itemID, statusID in
                                        handleOrderItemStatusSelection(order: order, itemID: itemID, statusID: statusID)
                                    }
                                )
                            } else if let inventory = message.inventory {
                                CRMInventoryCardView(
                                    inventory: inventory,
                                    statuses: referenceData.statuses.filter { $0.statusType == "inventory" },
                                    currencyTitleProvider: currencyTitle(for:),
                                    isSaving: updatingDocumentKey == documentKey(kind: "inventory", id: inventory.id),
                                    onOpen: {
                                        onOpenDocument("inventory", inventory.id)
                                    },
                                    onSelectStatus: { statusID in
                                        onSelectInventoryStatus(inventory, statusID)
                                    }
                                )
                            } else if let registration = message.productRegistration {
                                CRMProductRegistrationCardView(
                                    registration: registration,
                                    statuses: referenceData.statuses.filter { $0.statusType == "product_registration" },
                                    currencyTitleProvider: currencyTitle(for:),
                                    isSaving: updatingDocumentKey == documentKey(kind: "product_registration", id: registration.id),
                                    onOpen: {
                                        onOpenDocument("product_registration", registration.id)
                                    },
                                    onSelectStatus: { statusID in
                                        onSelectProductRegistrationStatus(registration, statusID)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, AppTheme.PageLayout.bottomPadding)
            }

            if let movementSelection {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.movementSelection = nil
                    }

                CRMMovementRouteSheet(
                    establishments: referenceData.establishments,
                    initialSourceEstablishmentID: movementSelection.sourceEstablishmentID,
                    initialDestinationEstablishmentID: movementSelection.destinationEstablishmentID,
                    onClose: {
                        self.movementSelection = nil
                    },
                    onConfirm: { sourceID, destinationID in
                        onSelectOrderItemStatus(
                            movementSelection.order,
                            movementSelection.itemID,
                            movementSelection.statusID,
                            sourceID,
                            destinationID
                        )
                        self.movementSelection = nil
                    }
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var orderItemStatuses: [HomeStatus] {
        referenceData.statuses.filter { $0.statusType == "order_products" }
    }

    private func currencyTitle(for currencyID: Int?) -> String {
        guard let currency = referenceData.currencies.first(where: { $0.id == currencyID }) else {
            return "USD"
        }
        if let sign = currency.currencySign, !sign.isEmpty {
            return sign
        }
        return currency.currencyName
    }

    private func documentKey(kind: String, id: Int) -> String {
        "\(kind):\(id)"
    }

    private func handleOrderItemStatusSelection(order: HomeOrder, itemID: Int, statusID: Int) {
        guard let item = order.items.first(where: { $0.id == itemID }) else { return }
        guard let status = orderItemStatuses.first(where: { $0.id == statusID }) else {
            onSelectOrderItemStatus(order, itemID, statusID, nil, nil)
            return
        }

        if status.statusStatus == "Перемещение" {
            movementSelection = CRMMovementSelection(
                order: order,
                itemID: itemID,
                statusID: statusID,
                sourceEstablishmentID: item.orderItemSourceEstablishmentID,
                destinationEstablishmentID: item.orderItemDestinationEstablishmentID
            )
            return
        }

        onSelectOrderItemStatus(order, itemID, statusID, nil, nil)
    }
}

private struct CRMMovementSelection: Identifiable {
    let order: HomeOrder
    let itemID: Int
    let statusID: Int
    let sourceEstablishmentID: Int?
    let destinationEstablishmentID: Int?

    var id: String {
        "\(order.id)-\(itemID)-\(statusID)"
    }
}

private struct CRMOrderCardView: View {
    let order: HomeOrder
    let orderMethods: [HomeOrderMethod]
    let itemStatuses: [HomeStatus]
    let statuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void
    let onSelectItemStatus: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Заказ №\(order.id)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(orderSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                CRMStatusMenu(
                    title: order.orderStatus ?? "Статус",
                    color: BusinessDocumentColors.statusColor(order.orderStatusColor),
                    statuses: statuses,
                    selectedStatusID: order.orderStatusID,
                    isDisabled: isSaving,
                    onSelect: onSelectStatus
                )
            }

            if !normalizedComment.isEmpty {
                Text(normalizedComment)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.white.opacity(0.34))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(order.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            CRMStatusMenu(
                                title: itemStatusTitle(for: item),
                                color: BusinessDocumentColors.statusColor(item.orderItemStatusColor),
                                statuses: itemStatuses,
                                selectedStatusID: item.orderItemStatusID,
                                size: .compact,
                                isDisabled: isSaving,
                                onSelect: { statusID in
                                    onSelectItemStatus(item.id, statusID)
                                }
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.orderItemName)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(item.orderItemQuantity) шт. * \(item.orderItemPrice)\(currencyTitleProvider(item.orderItemCurrencyID))")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()

                Text(orderTotalLine)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onOpen)
    }

    private var orderSubtitle: String {
        [order.orderEstablishmentName, methodTitle, order.orderCustomer]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " * ")
    }

    private var methodTitle: String? {
        let title = order.orderMethodName ?? orderMethods.first(where: { $0.id == order.orderMethodID })?.orderMethodName
        guard let title, !title.isEmpty else { return nil }
        guard let orderSubMethod = order.orderSubMethod, !orderSubMethod.isEmpty else {
            return title
        }
        return "\(title) * \(orderSubMethod)"
    }

    private var normalizedComment: String {
        order.orderInfo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var orderTotalLine: String {
        let totals = summarizedTotal(
            entries: order.items.map { (price: $0.orderItemPrice, quantity: $0.orderItemQuantity, currency: currencyTitleProvider($0.orderItemCurrencyID)) }
        )
        return totals.isEmpty ? "Итого: \(order.items.count) поз." : "Итого: \(totals)"
    }

    private func itemStatusTitle(for item: HomeOrderItem) -> String {
        if let status = item.orderItemStatus, !status.isEmpty {
            return status
        }
        return itemStatuses.first(where: { $0.id == item.orderItemStatusID })?.statusStatus ?? "Статус"
    }
}

private struct CRMInventoryCardView: View {
    let inventory: HomeInventory
    let statuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void

    var body: some View {
        CRMFlatDocumentCard(
            title: "Инвентаризация №\(inventory.id)",
            subtitle: [inventory.inventoryEstablishmentName, inventory.inventorySupplier]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " * "),
            comment: nil,
            statusTitle: inventory.inventoryStatus ?? "Статус",
            statusColor: BusinessDocumentColors.statusColor(inventory.inventoryStatusColor),
            statuses: statuses,
            selectedStatusID: inventory.inventoryStatusID,
            items: inventory.items.map {
                "\($0.inventoryItemName) * \($0.inventoryItemQuantity) шт. * \($0.inventoryItemCost)\(currencyTitleProvider($0.inventoryItemCurrencyID))"
            },
            totalLine: summarizedTotal(
                entries: inventory.items.map { (price: $0.inventoryItemCost, quantity: $0.inventoryItemQuantity, currency: currencyTitleProvider($0.inventoryItemCurrencyID)) }
            ),
            isSaving: isSaving,
            onOpen: onOpen,
            onSelectStatus: onSelectStatus
        )
    }
}

private struct CRMProductRegistrationCardView: View {
    let registration: HomeProductRegistration
    let statuses: [HomeStatus]
    let currencyTitleProvider: (Int?) -> String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void

    var body: some View {
        CRMFlatDocumentCard(
            title: "Приемка №\(registration.id)",
            subtitle: [registration.productRegistrationEstablishmentName, registration.productRegistrationSupplier]
                .compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " * "),
            comment: nil,
            statusTitle: registration.productRegistrationStatus ?? "Статус",
            statusColor: BusinessDocumentColors.statusColor(registration.productRegistrationStatusColor),
            statuses: statuses,
            selectedStatusID: registration.productRegistrationStatusID,
            items: registration.items.map {
                "\($0.productRegistrationItemName) * \($0.productRegistrationItemQuantity) шт. * \($0.productRegistrationItemCost)\(currencyTitleProvider($0.productRegistrationItemCurrencyID))"
            },
            totalLine: summarizedTotal(
                entries: registration.items.map { (price: $0.productRegistrationItemCost, quantity: $0.productRegistrationItemQuantity, currency: currencyTitleProvider($0.productRegistrationItemCurrencyID)) }
            ),
            isSaving: isSaving,
            onOpen: onOpen,
            onSelectStatus: onSelectStatus
        )
    }
}

private struct CRMFlatDocumentCard: View {
    let title: String
    let subtitle: String
    let comment: String?
    let statusTitle: String
    let statusColor: Color
    let statuses: [HomeStatus]
    let selectedStatusID: Int
    let items: [String]
    let totalLine: String
    let isSaving: Bool
    let onOpen: () -> Void
    let onSelectStatus: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                CRMStatusMenu(
                    title: statusTitle,
                    color: statusColor,
                    statuses: statuses,
                    selectedStatusID: selectedStatusID,
                    isDisabled: isSaving,
                    onSelect: onSelectStatus
                )
            }

            if let comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color.white.opacity(0.34))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            HStack {
                Spacer()

                Text(totalLine.isEmpty ? "Итого: \(items.count) поз." : "Итого: \(totalLine)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

private struct CRMStatusMenu: View {
    enum Size {
        case regular
        case compact

        var titleFontSize: CGFloat {
            switch self {
            case .regular:
                return 11
            case .compact:
                return 10
            }
        }

        var chevronFontSize: CGFloat {
            switch self {
            case .regular:
                return 9
            case .compact:
                return 8
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular:
                return 10
            case .compact:
                return 9
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .regular:
                return 7
            case .compact:
                return 5
            }
        }
    }

    let title: String
    let color: Color
    let statuses: [HomeStatus]
    let selectedStatusID: Int?
    let size: Size
    let isDisabled: Bool
    let onSelect: (Int) -> Void

    init(
        title: String,
        color: Color,
        statuses: [HomeStatus],
        selectedStatusID: Int?,
        size: Size = .regular,
        isDisabled: Bool,
        onSelect: @escaping (Int) -> Void
    ) {
        self.title = title
        self.color = color
        self.statuses = statuses
        self.selectedStatusID = selectedStatusID
        self.size = size
        self.isDisabled = isDisabled
        self.onSelect = onSelect
    }

    var body: some View {
        Menu {
            ForEach(statuses) { status in
                Button {
                    onSelect(status.id)
                } label: {
                    Text(status.statusStatus)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: size.titleFontSize, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: size.chevronFontSize, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke((selectedStatusID == nil ? Color.clear : color).opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || statuses.isEmpty)
    }
}

private struct CRMMovementRouteSheet: View {
    let establishments: [HomeEstablishment]
    let initialSourceEstablishmentID: Int?
    let initialDestinationEstablishmentID: Int?
    let onClose: () -> Void
    let onConfirm: (Int, Int) -> Void

    @State private var sourceEstablishmentID: Int?
    @State private var destinationEstablishmentID: Int?

    init(
        establishments: [HomeEstablishment],
        initialSourceEstablishmentID: Int?,
        initialDestinationEstablishmentID: Int?,
        onClose: @escaping () -> Void,
        onConfirm: @escaping (Int, Int) -> Void
    ) {
        self.establishments = establishments
        self.initialSourceEstablishmentID = initialSourceEstablishmentID
        self.initialDestinationEstablishmentID = initialDestinationEstablishmentID
        self.onClose = onClose
        self.onConfirm = onConfirm
        _sourceEstablishmentID = State(initialValue: initialSourceEstablishmentID)
        _destinationEstablishmentID = State(initialValue: initialDestinationEstablishmentID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Перемещение")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Выбери точки Откуда и Куда")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            routeSelector(title: "Откуда", selection: $sourceEstablishmentID)
            routeSelector(title: "Куда", selection: $destinationEstablishmentID)

            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    guard let sourceEstablishmentID, let destinationEstablishmentID else { return }
                    onConfirm(sourceEstablishmentID, destinationEstablishmentID)
                } label: {
                    Text("Сохранить")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sourceEstablishmentID == nil || destinationEstablishmentID == nil || sourceEstablishmentID == destinationEstablishmentID)
                .opacity(sourceEstablishmentID == nil || destinationEstablishmentID == nil || sourceEstablishmentID == destinationEstablishmentID ? 0.55 : 1)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func routeSelector(title: String, selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Menu {
                ForEach(establishments) { establishment in
                    Button {
                        selection.wrappedValue = establishment.id
                    } label: {
                        Text(establishment.establishmentName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(establishmentTitle(for: selection.wrappedValue) ?? "Выбери точку")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func establishmentTitle(for id: Int?) -> String? {
        establishments.first(where: { $0.id == id })?.establishmentName
    }
}

private func summarizedTotal(entries: [(price: String, quantity: Int, currency: String)]) -> String {
    guard !entries.isEmpty else { return "" }

    let currencies = Set(entries.map(\.currency))
    guard currencies.count == 1 else {
        return "\(entries.count) поз."
    }

    var total = Decimal.zero
    for entry in entries {
        let normalized = entry.price.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized) else {
            return "\(entries.count) поз."
        }
        total += value * Decimal(entry.quantity)
    }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2

    let number = NSDecimalNumber(decimal: total)
    let amount = formatter.string(from: number) ?? number.stringValue
    return "\(amount)\(currencies.first ?? "")"
}
