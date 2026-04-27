import SwiftUI

struct ChatOrderPreviewSheet: View {
    let order: HomeOrder
    let statuses: [HomeStatus]
    let itemStatuses: [HomeStatus]
    let errorMessage: String?
    let isSaving: Bool
    let currencyTitleProvider: (Int?) -> String
    let onClose: () -> Void
    let onSelectStatus: (Int) -> Void
    let onSelectItemStatus: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Заказ №\(order.id)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(order.orderCustomer)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                if isSaving {
                    ProgressView()
                        .tint(.white)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(statuses) { status in
                    let isSelected = status.id == order.orderStatusID

                    Button {
                        onSelectStatus(status.id)
                    } label: {
                        Text(status.statusStatus)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(isSelected ? statusColor(status.statusColor) : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Корзина")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(order.items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                HStack(spacing: 6) {
                                    Text(itemStatusTitle(for: item))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(itemStatusColor(for: item))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(itemStatusColor(for: item).opacity(0.16), in: Capsule())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.orderItemName)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }

                                Spacer()
                            }

                            HStack(spacing: 8) {
                                previewChip(title: "Кол-во", value: "\(item.orderItemQuantity)")
                                previewChip(title: "Цена", value: item.orderItemPrice)
                                previewChip(title: "Валюта", value: currencyTitleProvider(item.orderItemCurrencyID))
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 280)
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

    private func previewChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func itemStatusTitle(for item: HomeOrderItem) -> String {
        if let status = item.orderItemStatus, !status.isEmpty {
            return status
        }
        return itemStatuses.first(where: { $0.id == item.orderItemStatusID })?.statusStatus ?? "Статус"
    }

    private func itemStatusColor(for item: HomeOrderItem) -> Color {
        statusColor(item.orderItemStatusColor ?? itemStatuses.first(where: { $0.id == item.orderItemStatusID })?.statusColor)
    }

    private func statusColor(_ rawValue: String?) -> Color {
        let normalized = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "green":
            return Color(red: 0.16, green: 0.52, blue: 0.31)
        case "orange":
            return Color(red: 0.78, green: 0.44, blue: 0.12)
        case "blue":
            return Color(red: 0.20, green: 0.40, blue: 0.78)
        default:
            if normalized.hasPrefix("#"), let color = Color(hex: normalized) {
                return color
            }
            return Color.white.opacity(0.18)
        }
    }
}

private extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 || hex.count == 8, let int = UInt64(hex, radix: 16) else {
            return nil
        }

        let a, r, g, b: UInt64
        if hex.count == 8 {
            (a, r, g, b) = (int >> 24, int >> 16 & 0xff, int >> 8 & 0xff, int & 0xff)
        } else {
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xff, int & 0xff)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
