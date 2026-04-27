//
//  LoginView.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    
    @State private var userLogin = ""
    @State private var password = ""
    @State private var didAutoSubmitCurrentCredentials = false
    
    @FocusState private var focusedField: Field?
    private enum Field { case login, password }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    authBackground

                    ScrollView {
                        VStack(spacing: 10) {
                            Spacer(minLength: 28)

                            VStack(spacing: 18) {
                                Image("Brand_Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 232, height: 188)

                                VStack(spacing: 8) {
                                    Text("Вход в аккаунт")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("Продолжите работу в пространстве NufNaf")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.mutedText)
                                }
                                .multilineTextAlignment(.center)
                            }
                            .padding(.top, 36)
                            .padding(.bottom, 28)

                            VStack(spacing: 14) {
                                TextField("", text: $userLogin)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Auth.inputText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textContentType(.username)
                                    .submitLabel(.next)
                                    .tint(.black)
                                    .padding(AppTheme.LoginFormField.padding)
                                    .frame(width: AppTheme.LoginFormField.width, height: 50)
                                    .background(AppTheme.LoginFormField.placeholder)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous))
                                    .overlay {
                                        if userLogin.isEmpty {
                                            RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous)
                                                .fill(Color.clear)
                                                .overlay(alignment: .leading) {
                                                    Text("Login")
                                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                                        .foregroundStyle(AppTheme.LoginFormField.placeholderText)
                                                        .padding(.horizontal, AppTheme.LoginFormField.padding)
                                                }
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .focused($focusedField, equals: .login)
                                    .onSubmit {
                                        focusedField = .password
                                    }

                                SecureField("", text: $password)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Auth.inputText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textContentType(.password)
                                    .submitLabel(.go)
                                    .tint(.black)
                                    .padding(AppTheme.LoginFormField.padding)
                                    .frame(width: AppTheme.LoginFormField.width, height: 50)
                                    .background(AppTheme.LoginFormField.placeholder)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous))
                                    .overlay {
                                        if password.isEmpty {
                                            RoundedRectangle(cornerRadius: AppTheme.LoginFormField.cornerRadius, style: .continuous)
                                                .fill(Color.clear)
                                                .overlay(alignment: .leading) {
                                                    Text("Password")
                                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                                        .foregroundStyle(AppTheme.LoginFormField.placeholderText)
                                                        .padding(.horizontal, AppTheme.LoginFormField.padding)
                                                }
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .focused($focusedField, equals: .password)
                                    .onSubmit {
                                        submitLogin()
                                    }

                                if let errorMessage = session.authErrorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(AppTheme.dangerText)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .frame(width: AppTheme.LoginFormField.width, alignment: .leading)
                                        .padding(.top, 2)
                                }

                                Button {
                                    submitLogin()
                                } label: {
                                    HStack(spacing: 8) {
                                        if session.isBusy {
                                            ProgressView()
                                                .tint(.black)
                                        }

                                        Text(session.isBusy ? "Входим..." : "Login")
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(AppTheme.primaryButtonText)
                                    }
                                    .frame(width: AppTheme.LoginFormField.width, height: 50)
                                    .background(AppTheme.primaryButtonBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Auth.mediumCornerRadius, style: .continuous))
                                }
                                .padding(.top, 8)
                                .buttonStyle(.plain)
                                .disabled(!canSubmit)

                                if biometricLoginType != .none {
                                    Button {
                                        focusedField = nil

                                        Task {
                                            await session.loginWithBiometrics()
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: biometricLoginType.iconName)
                                                .font(.system(size: 17, weight: .semibold))

                                            Text(biometricLoginType.buttonTitle)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(width: AppTheme.LoginFormField.width, height: 50)
                                        .background(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppTheme.Auth.mediumCornerRadius, style: .continuous)
                                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Auth.mediumCornerRadius, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(session.isBusy)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 24)
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

                            NavigationLink {
                                PageTemplate {
                                    RegisterView()
                                }
                            } label: {
                                Text("Don't have account?")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryButtonText.opacity(0.8))
                                    .tracking(0.2)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.secondaryButtonBackground)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 28)
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isBusy)
                        }
                        .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                        .frame(minHeight: geometry.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(AppTheme.background)
                .ignoresSafeArea(.container, edges: .all)
                .navigationBarHidden(true)
                .onTapGesture {
                    focusedField = nil
                }
                .onAppear {
                    session.clearAuthError()
                }
                .onChange(of: userLogin) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        didAutoSubmitCurrentCredentials = false
                    }
                }
                .onChange(of: password) { oldValue, newValue in
                    handlePasswordChange(from: oldValue, to: newValue)
                }
            }
        }
    }

    private var trimmedLogin: String {
        userLogin.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !session.isBusy && !trimmedLogin.isEmpty && !password.isEmpty
    }

    private var biometricLoginType: AppBiometryType {
        session.biometricLoginType
    }

    private func submitLogin() {
        guard canSubmit else { return }
        focusedField = nil
        didAutoSubmitCurrentCredentials = true

        Task {
            await session.login(
                userLogin: trimmedLogin,
                password: password
            )
        }
    }

    private func handlePasswordChange(from oldValue: String, to newValue: String) {
        if newValue.isEmpty {
            didAutoSubmitCurrentCredentials = false
            return
        }

        let looksLikeSystemAutofill = oldValue.isEmpty && newValue.count >= 6
        guard looksLikeSystemAutofill,
              focusedField == .password,
              !didAutoSubmitCurrentCredentials,
              canSubmit else {
            return
        }

        submitLogin()
    }

    private var authBackground: some View {
        ZStack {
            AppTheme.background

            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 260
            )
            .offset(y: -90)

            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(.container, edges: .all)
    }
}

#Preview {
    LoginView()
        .environmentObject(AppSession())
}
