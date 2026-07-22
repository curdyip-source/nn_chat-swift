//
//  AppVersionGate.swift
//  myclearprojectIOS
//
//  Форс-апдейт: сервер (reference-data.min_supported_ios_build) задаёт минимальный
//  допустимый билд. Если текущий билд ниже — показываем блокирующий экран поверх
//  всего, пока пользователь не обновится. Порог рулится из веб-«Админки».
//

import Combine
import SwiftUI
import UIKit

@MainActor
final class AppVersionGate: ObservableObject {
    static let shared = AppVersionGate()

    /// Минимальный допустимый билд с сервера. 0 = гейт выключен.
    @Published var minBuild: Int = 0

    private init() {}

    /// Билд текущего приложения (CFBundleVersion).
    let currentBuild: Int = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Int(raw) ?? 0
    }()

    var isBlocked: Bool {
        minBuild > 0 && currentBuild < minBuild
    }

    func update(minBuild: Int) {
        self.minBuild = max(0, minBuild)
    }
}

/// Полноэкранный блокер «Обновите приложение». Недизмиссимый.
struct AppUpdateGateOverlay: View {
    @ObservedObject var gate: AppVersionGate

    var body: some View {
        if gate.isBlocked {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(Color(red: 0.39, green: 0.40, blue: 0.95))

                    Text("Обновите приложение")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Вышла новая версия. Чтобы продолжить работу, обновите приложение в TestFlight.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    Button {
                        openTestFlight()
                    } label: {
                        Text("Открыть TestFlight")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    Text("Ваш билд: \(gate.currentBuild) · нужен: \(gate.minBuild)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(32)
                .frame(maxWidth: 360)
            }
            .transition(.opacity)
            .zIndex(2000)
        }
    }

    private func openTestFlight() {
        // Пытаемся открыть приложение TestFlight; если его нет — страницу в App Store.
        if let tf = URL(string: "itms-beta://"), UIApplication.shared.canOpenURL(tf) {
            UIApplication.shared.open(tf)
        } else if let store = URL(string: "https://apps.apple.com/app/testflight/id899247664") {
            UIApplication.shared.open(store)
        }
    }
}
