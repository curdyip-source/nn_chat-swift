//
//  AppAlertCenter.swift
//  myclearprojectIOS
//
//  App-wide modal alert surface. Currently used for permission ("нет прав")
//  denials so they no longer hide as red inline text inside random cards or as
//  a failed-to-send order stuck in the chat — instead one overlay window is
//  shown on top of everything with a single "Хорошо" button.
//

import Combine
import SwiftUI

@MainActor
final class AppAlertCenter: ObservableObject {
    static let shared = AppAlertCenter()

    struct Alert: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        var icon: String = "exclamationmark.triangle.fill"
    }

    @Published var current: Alert?

    private init() {}

    /// Single unified permission-denied window. The backend's specific message is
    /// intentionally ignored in favour of one consistent wording.
    func showPermissionDenied() {
        // Do not stack duplicates if several failing calls land at once.
        guard current == nil else { return }
        current = Alert(
            title: "Недостаточно прав",
            message: "У вас недостаточно прав для этого действия.",
            icon: "lock.fill"
        )
    }

    /// Any other blocking message that has no inline surface to live in — e.g. a
    /// context-menu action that was refused (limit reached, action failed).
    func show(title: String, message: String, icon: String = "exclamationmark.triangle.fill") {
        current = Alert(title: title, message: message, icon: icon)
    }

    func dismiss() {
        current = nil
    }
}

extension Error {
    /// True when the failure is a backend permission denial (HTTP 403).
    var isPermissionDenied: Bool {
        if let authError = self as? AuthServiceError,
           case let .backend(statusCode, _) = authError {
            return statusCode == 403
        }
        return false
    }
}

/// Funnels an action error into the right surface: a permission denial (403) is
/// shown as the global "нет прав" overlay and yields `nil` so the caller hides
/// its inline red message; any other error is returned verbatim for the caller
/// to keep showing inline as before.
///
/// Safe to call from any actor context — the overlay hop is bounced to the main
/// actor internally.
func resolveActionError(_ error: Error) -> String? {
    if error.isPermissionDenied {
        Task { @MainActor in AppAlertCenter.shared.showPermissionDenied() }
        return nil
    }
    return error.localizedDescription
}

/// Root-level overlay that renders the current app alert on top of everything.
struct AppAlertOverlay: View {
    @ObservedObject var center: AppAlertCenter

    var body: some View {
        ZStack {
            if let alert = center.current {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { center.dismiss() }

                card(for: alert)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: center.current)
    }

    private func card(for alert: AppAlertCenter.Alert) -> some View {
        VStack(spacing: 14) {
            Image(systemName: alert.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.9))
                .padding(.top, 4)

            Text(alert.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(alert.message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                center.dismiss()
            } label: {
                Text("Хорошо")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 30, y: 12)
        .padding(.horizontal, 40)
    }
}
