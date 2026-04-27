//
//  RegisterView.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var userLogin = ""
    @State private var password = ""
    @State private var userSecondName = ""
    @State private var userFirstName = ""

    @FocusState private var focusedField: Field?
    private enum Field {
        case login
        case password
        case secondName
        case firstName
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.PageLayout.contentSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Создание аккаунта")
                            .font(AppTheme.PageHeader.titleFont)
                            .foregroundColor(.white)

                        Text("Заполните данные. После регистрации аккаунт попадёт на проверку администратору.")
                            .font(AppTheme.PageHeader.subtitleFont)
                            .foregroundColor(AppTheme.mutedText)
                    }
                    .padding(.bottom, 12)

                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            authField(
                                title: "Логин",
                                placeholder: "Логин",
                                text: $userLogin,
                                contentType: .username,
                                capitalization: .never,
                                submitLabel: .next
                            )
                            .focused($focusedField, equals: .login)
                            .onSubmit {
                                focusedField = .password
                            }

                            secureField(title: "Пароль", placeholder: "Пароль", text: $password)
                                .focused($focusedField, equals: .password)
                                .onSubmit {
                                    focusedField = .secondName
                                }

                            authField(
                                title: "Фамилия",
                                placeholder: "Фамилия",
                                text: $userSecondName,
                                contentType: .familyName,
                                capitalization: .words,
                                submitLabel: .next
                            )
                            .focused($focusedField, equals: .secondName)
                            .onSubmit {
                                focusedField = .firstName
                            }

                            authField(
                                title: "Имя",
                                placeholder: "Имя",
                                text: $userFirstName,
                                contentType: .givenName,
                                capitalization: .words,
                                submitLabel: .go
                            )
                            .focused($focusedField, equals: .firstName)
                            .onSubmit {
                                submitRegistration()
                            }
                        }

                        if let errorMessage = session.authErrorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.dangerText)
                        }

                        Button {
                            submitRegistration()
                        } label: {
                            HStack(spacing: 8) {
                                if session.isBusy {
                                    ProgressView()
                                        .tint(.black)
                                }

                                Text(session.isBusy ? "Создаём..." : "Создать аккаунт")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.primaryButtonText)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppTheme.primaryButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Auth.mediumCornerRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy || !isFormValid)
                        .padding(.top, 8)
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Auth.largeCornerRadius, style: .continuous)
                            .fill(AppTheme.Auth.surfaceBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Auth.largeCornerRadius, style: .continuous)
                                    .stroke(AppTheme.Auth.surfaceStroke, lineWidth: 1)
                            )
                            .shadow(color: AppTheme.Auth.surfaceShadow, radius: 18, x: 0, y: 10)
                    )

                    Button("У меня уже есть аккаунт") {
                        session.clearAuthError()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(AppTheme.secondaryButtonBackground)
                    .clipShape(Capsule())
                    .disabled(session.isBusy)

                    Spacer()
                }
                .padding(.top, AppTheme.PageLayout.topPadding)
                .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                .padding(.bottom, AppTheme.PageLayout.bottomPadding)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
            .onAppear {
                session.clearAuthError()
            }
        }
    }

    private var isFormValid: Bool {
        userLogin.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        && password.count >= 6
        && !userSecondName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !userFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitRegistration() {
        guard isFormValid, !session.isBusy else { return }
        focusedField = nil

        Task {
            await session.register(
                userLogin: userLogin.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                firstName: userFirstName.trimmingCharacters(in: .whitespacesAndNewlines),
                secondName: userSecondName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func authField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType?,
        capitalization: TextInputAutocapitalization,
        submitLabel: SubmitLabel
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))

            TextField("", text: text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Auth.inputText)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .tint(.black)
                .padding(AppTheme.RegisterFormField.padding)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.RegisterFormField.height)
                .background(AppTheme.LoginFormField.placeholder)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous))
                .overlay {
                    if text.wrappedValue.isEmpty {
                        RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous)
                            .fill(Color.clear)
                            .overlay(alignment: .leading) {
                                Text(placeholder)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.LoginFormField.placeholderText)
                                    .padding(.horizontal, AppTheme.LoginFormField.padding)
                            }
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func secureField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))

            SecureField("", text: text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Auth.inputText)
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .tint(.black)
                .padding(AppTheme.RegisterFormField.padding)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.RegisterFormField.height)
                .background(AppTheme.LoginFormField.placeholder)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous))
                .overlay {
                    if text.wrappedValue.isEmpty {
                        RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous)
                            .fill(Color.clear)
                            .overlay(alignment: .leading) {
                                Text(placeholder)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.LoginFormField.placeholderText)
                                    .padding(.horizontal, AppTheme.LoginFormField.padding)
                            }
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

#Preview {
    PageTemplate {
        RegisterView()
    }
    .environmentObject(AppSession())
}
