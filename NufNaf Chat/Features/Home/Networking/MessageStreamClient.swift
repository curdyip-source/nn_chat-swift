//
//  MessageStreamClient.swift
//  NufNaf Chat
//
//  Server-Sent Events client for /messages/stream. Yields realtime created/updated/deleted
//  events so the chat feed (and the order/inventory/registration cards it embeds) update
//  live without polling. The caller reconnects on stream end and delta-syncs to catch up.
//

import Foundation

struct MessageStreamClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// A stream of decoded events. Finishes when the connection closes; throws on a network or
    /// non-2xx error so the caller can back off and reconnect.
    func events(accessToken: String) -> AsyncThrowingStream<MessageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("messages/stream"))
                    request.timeoutInterval = 86_400
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw AuthServiceError.backend(statusCode: code, message: "Не удалось открыть поток")
                    }

                    var dataBuffer = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            // Blank line terminates an SSE event.
                            if !dataBuffer.isEmpty,
                               let payload = dataBuffer.data(using: .utf8),
                               let event = try? JSONDecoder().decode(MessageStreamEvent.self, from: payload) {
                                continuation.yield(event)
                            }
                            dataBuffer = ""
                        } else if line.hasPrefix("data:") {
                            dataBuffer += line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        }
                        // Lines starting with ":" are heartbeats/comments and are ignored.
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
