//
//  AppConfig.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import Foundation

enum AppConfig {
    static var apiBaseURL: URL {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return url
        }

        guard let fallbackURL = URL(string: "https://mgdb.myds.me:25257/api/v1") else {
            preconditionFailure("Invalid fallback API URL")
        }
        return fallbackURL
    }

    static var mediaBaseURL: URL {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: "MEDIA_BASE_URL") as? String,
           let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return url
        }

        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            return apiBaseURL
        }
        components.path = "/media"
        components.query = nil
        components.fragment = nil
        return components.url ?? apiBaseURL
    }

    static func mediaURL(for value: String?) -> URL? {
        guard let value else { return nil }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else { return nil }
        if normalizedValue.contains("://") {
            return URL(string: normalizedValue)
        }
        return mediaBaseURL.appending(path: normalizedValue)
    }

    static func messageAttachmentURL(for attachmentID: Int) -> URL? {
        mediaBaseURL.appending(path: "message-attachments").appending(path: String(attachmentID))
    }

    static func orderCommentAttachmentURL(for attachmentID: Int) -> URL? {
        mediaBaseURL.appending(path: "order-comment-attachments").appending(path: String(attachmentID))
    }
}
