//
//  myclearprojectIOSApp.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct myclearprojectIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .task {
                    await session.restoreSession()
                }
                .task(id: session.currentAccessToken ?? "no-token") {
                    await AppNotificationManager.shared.syncRemoteNotifications(accessToken: session.currentAccessToken)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            AppNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
}

@MainActor
final class AppNotificationManager {
    static let shared = AppNotificationManager()

    private let client = HomeAPIClient()
    private let defaults = UserDefaults.standard
    private let deviceTokenKey = "notifications.device-token"
    private var currentAccessToken: String?

    private init() {}

    func syncRemoteNotifications(accessToken: String?) async {
        currentAccessToken = accessToken
        guard accessToken != nil else { return }
        await requestAuthorizationIfNeeded()
        await registerPendingDeviceTokenIfPossible()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: deviceTokenKey)
        Task {
            await registerPendingDeviceTokenIfPossible()
        }
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            return
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        case .denied:
            return
        @unknown default:
            return
        }
    }

    private func registerPendingDeviceTokenIfPossible() async {
        guard let accessToken = currentAccessToken,
              let deviceToken = defaults.string(forKey: deviceTokenKey),
              !deviceToken.isEmpty else {
            return
        }

        try? await client.registerUserDevice(accessToken: accessToken, token: deviceToken)
    }
}
