//
//  ProfileEditorView.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditorView: View {
    @EnvironmentObject private var session: AppSession
    @FocusState private var isInputFocused: Bool
    @State private var firstName: String
    @State private var secondName: String
    @State private var profilePhoto: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var age: String
    @State private var address: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let user: AuthUser
    let store: HomeStore
    let onClose: () -> Void
    let onUserUpdated: (AuthUser) -> Void

    init(user: AuthUser, store: HomeStore, onClose: @escaping () -> Void, onUserUpdated: @escaping (AuthUser) -> Void) {
        self.user = user
        self.store = store
        self.onClose = onClose
        self.onUserUpdated = onUserUpdated
        _firstName = State(initialValue: user.userFirstName)
        _secondName = State(initialValue: user.userSecondName)
        _profilePhoto = State(initialValue: user.userProfilePhoto ?? "")
        _age = State(initialValue: String(user.userAge))
        _address = State(initialValue: user.userAddress)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Профиль")
                                .font(AppTheme.PageHeader.titleFont)
                                .foregroundStyle(.white)

                            Text("Редактирование фото и основных данных пользователя")
                                .font(AppTheme.PageHeader.subtitleFont)
                                .foregroundStyle(AppTheme.mutedText)
                        }

                        Spacer(minLength: 12)
                    }

                    HStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.10))

                            if let selectedPhotoData,
                               let image = UIImage(data: selectedPhotoData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else if let url = AppConfig.mediaURL(for: profilePhoto) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            } else {
                                Text(initials)
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Фото профиля")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.64))

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack {
                                    Image(systemName: "photo.on.rectangle.angled")
                                    Text("Выбрать из галереи")
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if selectedPhotoData != nil || !profilePhoto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("Убрать фото") {
                                    selectedPhotoData = nil
                                    selectedPhotoItem = nil
                                    profilePhoto = ""
                                }
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.78))
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Group {
                        profileField(title: "Фамилия", text: $secondName)
                        profileField(title: "Имя", text: $firstName)
                        profileField(title: "Возраст", text: $age, keyboard: .numberPad)
                        profileField(title: "Адрес", text: $address)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.dangerText)
                    }

                    Button {
                        Task {
                            await saveProfile()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Сохранить")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.black)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
                .padding(.top, AppTheme.PageLayout.topPadding)
                .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                Button {
                    Task {
                        await session.logout()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Выйти из аккаунта")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, AppTheme.PageLayout.bottomPadding)
            }
            .background(Color.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await loadSelectedPhoto(from: newItem)
            }
        }
    }

    private var initials: String {
        let first = secondName.prefix(1)
        let second = firstName.prefix(1)
        return "\(first)\(second)".uppercased()
    }

    private func profileField(title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))

            TextField(title, text: text)
                .focused($isInputFocused)
                .keyboardType(keyboard)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func saveProfile() async {
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondName = secondName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFirstName.isEmpty else {
            errorMessage = "Имя не должно быть пустым"
            return
        }

        guard !trimmedSecondName.isEmpty else {
            errorMessage = "Фамилия не должна быть пустой"
            return
        }

        guard !trimmedAddress.isEmpty else {
            errorMessage = "Адрес не должен быть пустым"
            return
        }

        guard let ageValue = Int(age) else {
            errorMessage = "Возраст должен быть числом"
            return
        }

        var request = HomeProfileUpdateRequest()

        var latestUser = user
        var didUploadPhoto = false

        if let selectedPhotoData {
            do {
                latestUser = try await store.uploadProfilePhoto(accessToken: session.currentAccessToken, jpegData: selectedPhotoData)
                profilePhoto = latestUser.userProfilePhoto ?? ""
                self.selectedPhotoData = nil
                selectedPhotoItem = nil
                didUploadPhoto = true
            } catch let error as AuthServiceError {
                errorMessage = error.errorDescription
                return
            } catch {
                errorMessage = "Не удалось загрузить фото профиля"
                return
            }
        }

        let trimmedProfilePhoto = profilePhoto.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedFirstName != latestUser.userFirstName {
            request.userFirstName = trimmedFirstName
        }
        if trimmedSecondName != latestUser.userSecondName {
            request.userSecondName = trimmedSecondName
        }
        if ageValue != latestUser.userAge {
            request.userAge = ageValue
        }
        if trimmedAddress != latestUser.userAddress {
            request.userAddress = trimmedAddress
        }

        let normalizedExistingPhoto = (latestUser.userProfilePhoto ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedProfilePhoto != normalizedExistingPhoto {
            request.userProfilePhoto = trimmedProfilePhoto.isEmpty ? nil : trimmedProfilePhoto
        }

        let hasRemoteChanges = request.userFirstName != nil
            || request.userSecondName != nil
            || request.userAge != nil
            || request.userAddress != nil
            || trimmedProfilePhoto != normalizedExistingPhoto

        if !hasRemoteChanges && !didUploadPhoto {
            errorMessage = "Нет изменений для сохранения"
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if hasRemoteChanges {
                let updatedUser = try await store.saveProfile(
                    accessToken: session.currentAccessToken,
                    request: request
                )
                onUserUpdated(updatedUser)
            } else {
                onUserUpdated(latestUser)
            }
            onClose()
        } catch let error as AuthServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Не удалось сохранить профиль"
        }
    }

    private func loadSelectedPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Не удалось прочитать выбранное фото"
                return
            }

            guard let optimizedData = optimizedJPEGData(from: data) else {
                await MainActor.run {
                    errorMessage = "Не удалось подготовить фото к загрузке"
                }
                return
            }

            await MainActor.run {
                selectedPhotoData = optimizedData
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось открыть фото из галереи"
            }
        }
    }

    private func optimizedJPEGData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let maxDimension: CGFloat = 1024
        let originalSize = image.size
        let scale = min(maxDimension / max(originalSize.width, originalSize.height), 1)
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return renderedImage.jpegData(compressionQuality: 0.82)
    }
}
