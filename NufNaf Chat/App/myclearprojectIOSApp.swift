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
    @StateObject private var notificationRouter = NotificationRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(session)
                .environmentObject(notificationRouter)
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationRouter.shared.handle(userInfo: response.notification.request.content.userInfo)
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

        try? await client.registerUserDevice(
            accessToken: accessToken,
            token: deviceToken,
            environment: APNsEnvironment.current.rawValue
        )
    }
}

/// APNs delivery environment the current build's device token belongs to.
///
/// A token minted by a `development` (sandbox) build can only be delivered through
/// the sandbox gateway, and a `production` token only through the production gateway.
/// The token string itself carries no hint of its environment, so the backend needs
/// us to tell it which gateway to use — otherwise local dev builds (sandbox) silently
/// fail while TestFlight/App Store builds (production) keep working.
enum APNsEnvironment: String {
    case sandbox
    case production

    /// Resolved from the embedded provisioning profile's `aps-environment` entitlement.
    /// `development` → sandbox; everything else (including App Store builds, which ship
    /// without an embedded profile) → production.
    static let current: APNsEnvironment = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // The profile is a CMS-signed blob; the embedded plist is plain text in it.
              let content = String(data: data, encoding: .isoLatin1),
              let start = content.range(of: "<?xml"),
              let end = content.range(of: "</plist>") else {
            return .production
        }

        let plistString = String(content[start.lowerBound ..< end.upperBound])
        guard let plistData = plistString.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let apsEnvironment = entitlements["aps-environment"] as? String else {
            return .production
        }

        return apsEnvironment == "development" ? .sandbox : .production
    }()
}
