//
//  AppConfirmCard.swift
//  myclearprojectIOS
//
//  Переиспользуемая карточка-подтверждение поверх экрана — в едином стиле приложения
//  (как «Поставщик»/«нет прав»), вместо нативных confirmationDialog снизу. Кнопки
//  стекаются вертикально, поэтому влезают подписи любой длины.
//

import SwiftUI

struct AppConfirmButton: Identifiable {
    enum Style { case primary, destructive, cancel }
    let id = UUID()
    let label: String
    let style: Style
    let action: () -> Void
}

struct AppConfirmCard: View {
    let title: String
    let message: String
    let buttons: [AppConfirmButton]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(buttons) { button in
                        Button(action: button.action) {
                            Text(button.label)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground(button.style))
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(background(button.style), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.15, blue: 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 30, y: 12)
            .padding(.horizontal, 32)
        }
    }

    private func foreground(_ style: AppConfirmButton.Style) -> Color {
        switch style {
        case .primary: return .black
        case .destructive: return .white
        case .cancel: return .white.opacity(0.9)
        }
    }

    private func background(_ style: AppConfirmButton.Style) -> Color {
        switch style {
        case .primary: return Color(red: 0.48, green: 0.84, blue: 0.60)
        case .destructive: return Color(red: 0.78, green: 0.25, blue: 0.29)
        case .cancel: return Color.white.opacity(0.10)
        }
    }
}
