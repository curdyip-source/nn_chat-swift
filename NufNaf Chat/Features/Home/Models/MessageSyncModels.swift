//
//  MessageSyncModels.swift
//  NufNaf Chat
//
//  Models for incremental chat sync (/messages/sync) and the realtime SSE stream
//  (/messages/stream). The feed is delta-synced against a server cursor and kept live
//  over SSE, so history is cached locally instead of refetched in full.
//

import Foundation

/// One item from a delta-sync page: either a live message or a tombstone for a deleted one.
enum HomeMessageSyncItem: Decodable {
    case message(HomeMessage)
    case tombstone(id: Int)

    private enum Keys: String, CodingKey {
        case messageID = "message_id"
        case messageDeleted = "message_deleted"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let deleted = (try? container.decode(Bool.self, forKey: .messageDeleted)) ?? false
        if deleted {
            self = .tombstone(id: try container.decode(Int.self, forKey: .messageID))
        } else {
            self = .message(try HomeMessage(from: decoder))
        }
    }
}

struct HomeMessageSyncResponse: Decodable {
    let items: [HomeMessageSyncItem]
    let cursor: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case cursor
        case hasMore = "has_more"
    }
}

/// A realtime event pushed over SSE. `message` is present for created/updated; `messageID`
/// identifies the row for deleted.
struct MessageStreamEvent: Decodable {
    let type: String
    let message: HomeMessage?
    let messageID: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case message
        case messageID = "message_id"
    }
}
