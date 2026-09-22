//
//  SystemMessageCenter.swift
//  myclearprojectIOS
//
//  Системные сообщения из веб-«Админки»: блокирующий оверлей (наш AppConfirmCard),
//  который нельзя закрыть мимо — только явным «Прочитано». «Важные» сообщения
//  дополнительно переспрашивают «Вы точно ознакомились?» перед тем, как реально
//  снять с очереди — часто такие сообщения закрывают не глядя, это лишний барьер.
//
//  Доставка: GET /system-messages/pending при каждом старте (на случай, если
//  получатель был оффлайн в момент отправки) + SSE-сигнал «system_message_created»,
//  пока приложение открыто (HomeStore перечитывает список заново — сам эвент
//  содержимого не несёт, чтобы не светить текст/адресатов всем подписчикам SSE).
//

import Combine
import SwiftUI

@MainActor
final class SystemMessageCenter: ObservableObject {
    static let shared = SystemMessageCenter()

    enum Stage: Equatable {
        /// Первый экран: текст сообщения + «Прочитано».
        case message
        /// Только для important — переспрос перед реальным подтверждением.
        case confirmImportant
    }

    /// Очередь неподтверждённых сообщений — показываем по одному, старые первыми.
    @Published private(set) var queue: [HomeSystemMessage] = []
    @Published private(set) var stage: Stage?

    private var client: HomeAPIClient?
    private var accessToken: String?
    private var isAcking = false

    private init() {}

    var current: HomeSystemMessage? { queue.first }

    /// Перечитать список с сервера — при старте приложения и по SSE-сигналу.
    func refresh(client: HomeAPIClient, accessToken: String) {
        self.client = client
        self.accessToken = accessToken
        Task { [weak self] in
            guard let self, let items = try? await client.fetchPendingSystemMessages(accessToken: accessToken) else { return }
            await MainActor.run {
                self.queue = items
                self.stage = items.isEmpty ? nil : .message
            }
        }
    }

    /// Тап «Прочитано»: обычное сообщение подтверждаем сразу, важное — сперва переспрашиваем.
    func acknowledgeTapped() {
        guard let message = current else { return }
        if message.important {
            stage = .confirmImportant
        } else {
            confirmFinal()
        }
    }

    /// «Вернуться к сообщению» на шаге переспроса — НЕ снимает сообщение с очереди.
    func cancelConfirm() {
        stage = .message
    }

    /// Финальное подтверждение — единственный путь снять сообщение с очереди.
    func confirmFinal() {
        guard let message = current, !isAcking, let client, let accessToken else { return }
        isAcking = true
        Task { [weak self] in
            try? await client.acknowledgeSystemMessage(accessToken: accessToken, messageID: message.id)
            await MainActor.run {
                guard let self else { return }
                self.isAcking = false
                if !self.queue.isEmpty {
                    self.queue.removeFirst()
                }
                self.stage = self.queue.isEmpty ? nil : .message
            }
        }
    }
}

/// Блокирующий оверлей системного сообщения — поверх всего (см. ContentView), без
/// возможности закрыть тапом мимо: у AppConfirmCard нет фонового dismiss-жеста.
struct SystemMessageOverlay: View {
    @ObservedObject var center: SystemMessageCenter

    var body: some View {
        if let message = center.current, let stage = center.stage {
            switch stage {
            case .message:
                AppConfirmCard(
                    title: "Системное сообщение",
                    message: message.text,
                    buttons: [
                        AppConfirmButton(label: "Прочитано", style: .primary) {
                            center.acknowledgeTapped()
                        }
                    ]
                )
                .transition(.opacity)

            case .confirmImportant:
                AppConfirmCard(
                    title: "Вы точно ознакомились?",
                    message: "Это важное системное сообщение — вернитесь и перечитайте его, если не уверены.",
                    buttons: [
                        AppConfirmButton(label: "Да, подтверждаю", style: .primary) {
                            center.confirmFinal()
                        },
                        AppConfirmButton(label: "Вернуться к сообщению", style: .cancel) {
                            center.cancelConfirm()
                        },
                    ]
                )
                .transition(.opacity)
            }
        }
    }
}
