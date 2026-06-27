//
//  NotificationRouter.swift
//  NufNaf Chat
//
//  Routes tapped push notifications (mentions) to the right chat destination.
//

import Combine
import Foundation

enum NotificationRoute: Equatable {
    case chatMessage(id: Int)
    case order(id: Int)
}

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published var pendingRoute: NotificationRoute?
    /// Bumped whenever a push arrives while the app is in the foreground, so open screens can
    /// refresh immediately instead of waiting for the next poll tick (push beats the 4s poll).
    @Published private(set) var foregroundPushTick: Int = 0

    private init() {}

    func noteForegroundPush() {
        foregroundPushTick &+= 1
    }

    func handle(userInfo: [AnyHashable: Any]) {
        guard let eventType = userInfo["event_type"] as? String,
              let entityID = Self.intValue(userInfo["entity_id"]) else {
            return
        }

        switch eventType {
        case "mention_chat":
            pendingRoute = .chatMessage(id: entityID)
        case "mention_order", "order_updated", "order":
            pendingRoute = .order(id: entityID)
        default:
            break
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}
