//
//  MessageStreamClient.swift
//  NufNaf Chat
//
//  Server-Sent Events client for /messages/stream. Yields realtime created/updated/deleted
//  events so the chat feed (and the order/inventory/registration cards it embeds) update
//  live without polling. The caller reconnects on stream end and delta-syncs to catch up.
//
//  Uses a URLSessionDataDelegate (not URLSession.bytes) so each chunk is delivered the instant
//  it arrives — URLSession.bytes was buffering the stream on device, defeating realtime.
//

import Foundation

struct MessageStreamClient {
    private let baseURL: URL

    init(baseURL: URL = AppConfig.apiBaseURL) {
        self.baseURL = baseURL
    }

    /// A stream of raw SSE event payloads (the JSON after `data:`). Decoding is left to the
    /// caller (which runs on the main actor) — the model's Decodable conformance is main-actor
    /// isolated and can't be used from this background delegate under Swift 6. Finishes when the
    /// connection closes; throws on a network or non-2xx error so the caller can reconnect.
    func events(accessToken: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            var request = URLRequest(url: baseURL.appendingPathComponent("messages/stream"))
            request.timeoutInterval = 86_400
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.assumesHTTP3Capable = false

            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 86_400
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = true

            let delegate = SSEDelegate(continuation: continuation)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)

            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }

            task.resume()
        }
    }
}

/// Parses an SSE byte stream incrementally as chunks arrive and yields raw event payloads.
private final class SSEDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var buffer = Data()

    init(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            continuation.finish(throwing: AuthServiceError.backend(statusCode: code, message: "Не удалось открыть поток"))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        // SSE events are separated by a blank line ("\n\n").
        let separator = Data([0x0A, 0x0A])
        while let range = buffer.range(of: separator) {
            let rawEvent = buffer.subdata(in: buffer.startIndex ..< range.lowerBound)
            buffer.removeSubrange(buffer.startIndex ..< range.upperBound)
            emit(rawEvent)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    private func emit(_ rawEvent: Data) {
        guard let text = String(data: rawEvent, encoding: .utf8) else { return }
        let payload = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst("data:".count).trimmingCharacters(in: .whitespaces) }
            .joined()
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else {
            return // heartbeat/comment
        }
        continuation.yield(data)
    }
}
