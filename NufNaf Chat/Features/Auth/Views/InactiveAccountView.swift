//
//  InactiveAccountView.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import SwiftUI

struct InactiveAccountView: View {
    let user: AuthUser
    let onBackToLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.PageLayout.contentSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Аккаунт создан")
                    .font(AppTheme.PageHeader.titleFont)
                    .foregroundColor(.white)

                Text("\(displayName), ваша заявка отправлена. Дождитесь, пока администратор активирует аккаунт.")
                    .font(AppTheme.PageHeader.subtitleFont)
                    .foregroundColor(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Логин")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))

                    Text(user.userLogin)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.Auth.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Auth.mediumCornerRadius, style: .continuous))
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Auth.largeCornerRadius, style: .continuous)
                    .fill(AppTheme.Auth.surfaceBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Auth.largeCornerRadius, style: .continuous)
                            .stroke(AppTheme.Auth.surfaceStroke, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.Auth.surfaceShadow, radius: 18, x: 0, y: 10)
            )

            Spacer()

            Button(action: onBackToLogin) {
                Text("Вернуться ко входу")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppTheme.primaryButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Auth.mediumCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, AppTheme.PageLayout.topPadding)
        .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
        .padding(.bottom, AppTheme.PageLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayName: String {
        let fullName = "\(user.userSecondName) \(user.userFirstName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "Пользователь" : fullName
    }
}

#Preview {
    PageTemplate {
        InactiveAccountView(
            user: AuthUser(
                userID: 1,
                userLogin: "demo",
                userAdmin: false,
                userActive: false,
                userFirstName: "Иван",
                userSecondName: "Иванов",
                userProfilePhoto: nil,
                userAge: 0,
                userAddress: "-",
                userVerifiedUserID: nil,
                userCreatedAt: nil
            ),
            onBackToLogin: {}
        )
    }
    .environmentObject(AppSession())
}
