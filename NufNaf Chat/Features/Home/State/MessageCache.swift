//
//  MessageCache.swift
//  NufNaf Chat
//
//  On-disk cache of the chat feed (server messages + sync cursor), keyed per user so the
//  app shows history instantly on launch and only delta-syncs the changes since last run.
//

import Foundation

struct CachedChatFeed: Codable {
    var messages: [HomeMessage]
    var cursor: String?
}

struct MessageCache {
    let userID: Int

    private static let folderName = "ChatFeedCache"

    private var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = support.appendingPathComponent(Self.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("feed-\(userID).json")
    }

    func load() -> CachedChatFeed? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedChatFeed.self, from: data)
    }

    func save(_ feed: CachedChatFeed) {
        guard let fileURL, let data = try? JSONEncoder().encode(feed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
