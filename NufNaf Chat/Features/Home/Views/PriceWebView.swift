//
//  PriceWebView.swift
//  NufNaf Chat
//
//  Режим «Прайс» — встраивает адаптированную под телефон веб-секцию прайса
//  (<webBaseURL>/?embed=price) в WKWebView. Bearer-токен приложения инжектится в
//  localStorage веба (ключи admin.accessToken / admin.refreshToken) до загрузки —
//  веб авторизуется сам и сам рефрешит токен. Единый вход, отдельного логина нет.
//

import SwiftUI
import WebKit

struct PriceWebView: UIViewRepresentable {
    let accessToken: String?
    let refreshToken: String?

    func makeCoordinator() -> Coordinator { Coordinator(token: accessToken) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        installTokenScript(into: controller)

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = .clear
        webView.isOpaque = false

        if let url = Self.embedURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Токен приложения обновился (рефреш) — переинжектим и перезагрузим, чтобы веб
        // не остался со старым токеном (рефреши редкие, потеря состояния допустима).
        guard context.coordinator.token != accessToken else { return }
        context.coordinator.token = accessToken
        webView.configuration.userContentController.removeAllUserScripts()
        installTokenScript(into: webView.configuration.userContentController)
        if let url = Self.embedURL {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator {
        var token: String?
        init(token: String?) { self.token = token }
    }

    private func installTokenScript(into controller: WKUserContentController) {
        guard let script = Self.tokenScript(access: accessToken, refresh: refreshToken) else { return }
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private static var embedURL: URL? {
        var components = URLComponents(url: AppConfig.webBaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.queryItems = [URLQueryItem(name: "embed", value: "price")]
        return components?.url
    }

    private static func tokenScript(access: String?, refresh: String?) -> String? {
        guard let access, !access.isEmpty else { return nil }
        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        }
        var lines = ["try { localStorage.setItem('admin.accessToken', '\(escaped(access))'); } catch (e) {}"]
        if let refresh, !refresh.isEmpty {
            lines.append("try { localStorage.setItem('admin.refreshToken', '\(escaped(refresh))'); } catch (e) {}")
        }
        return lines.joined(separator: "\n")
    }
}
