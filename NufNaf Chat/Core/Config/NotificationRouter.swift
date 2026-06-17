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

    private init() {}

    func handle(userInfo: [AnyHashable: Any]) {
        guard let eventType = userInfo["event_type"] as? String,
              let entityID = Self.intValue(userInfo["entity_id"]) else {
            return
        }

        switch eventType {
        case "mention_chat":
            pendingRoute = .chatMessage(id: entityID)
        case "mention_order":
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
