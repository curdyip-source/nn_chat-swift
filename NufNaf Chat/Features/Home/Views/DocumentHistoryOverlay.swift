import SwiftUI
import UIKit

/// Окно истории документа (заказ, инвентаризация, приёмка) — выезжает снизу, как
/// форма редактирования. Записи приходят с бэкенда новыми сверху, формат один на все
/// документы (`/history` у каждого).
struct DocumentHistoryOverlay: View {
    let title: String
    let entries: [HomeOrderHistoryEntry]
    let isLoading: Bool
    let errorMessage: String?
    let onClose: () -> Void

    /// Высота ленты: окно должно быть по содержимому, а не на весь экран —
    /// список внутри ScrollView иначе растягивается на всю доступную высоту.
    @State private var contentHeight: CGFloat = 0

    // Эмодзи под тип события — те же, что в истории на сайте (иконотеки в проекте нет).
    private static let kindIcons: [String: String] = [
        "create": "🆕",
        "order_status": "🔄",
        // Смена статуса инвентаризации/приёмки.
        "status": "🔄",
        "item_status": "📦",
        // На сайте для оплаты значка нет и рисуется точка-заглушка — здесь свой.
        "order_paid": "💰",
        "edit": "✏️",
        "split": "✂️",
        "comment": "💬",
        "delete": "🗑️",
        "cdek": "🚚",
    ]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yy, HH:mm"
        return formatter
    }()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))

                        Spacer(minLength: 12)

                        Button("Закрыть", action: onClose)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(Capsule())
                    }

                    if isLoading, entries.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Загрузка…")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if entries.isEmpty {
                        Text("История пуста")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                // Одно событие может дать несколько записей, поэтому
                                // различаем их по позиции в ленте.
                                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                    row(entry)
                                }
                            }
                            .padding(.bottom, 4)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                contentHeight = height
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        // Короткая история — короткое окно; длинная упирается в потолок и скроллится.
                        .frame(height: min(max(contentHeight, 44), proxy.size.height * 0.9 - 120))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .frame(maxHeight: proxy.size.height * 0.9, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: -4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                // Светлое окно в тёмном приложении — как форма создания и редактирования.
                .environment(\.colorScheme, .light)
            }
        }
    }

    private func row(_ entry: HomeOrderHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.kindIcons[entry.kind] ?? "•")
                .font(.system(size: 15))
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(Text(entry.actorName).fontWeight(.semibold)) \(entry.text)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(time(entry.createdAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func time(_ rawValue: String?) -> String {
        guard let date = HomeMessageDateParser.parse(rawValue) else { return "" }
        return Self.dateFormatter.string(from: date)
    }
}
