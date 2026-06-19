//
//  ChatConversationView.swift
//  NufNaf Chat
//
//  UIKit-ядро чата: инвертированный UICollectionView (ячейки рендерят
//  существующие SwiftUI-вьюхи через UIHostingConfiguration) + композер,
//  привязанный к keyboardLayoutGuide для нативной синхронизации с клавиатурой.
//

import SwiftUI
import UIKit

// MARK: - Модель строки списка

nonisolated enum ChatRowID: Hashable {
    case separator(String)
    case message(Int)
}

struct ChatRow {
    enum Kind {
        case separator(String)
        case message(HomeMessage, showsSenderName: Bool)
    }

    let id: ChatRowID
    let kind: Kind
    /// Дешёвая сигнатура отображаемого контента (без глубокого хеша вложенных
    /// order/attachments). Используется для детекта изменений вместо хеша всего HomeMessage.
    let contentHash: Int
}

// MARK: - Построение строк (порядок: визуальный сверху вниз, oldest -> newest)

enum ChatRowBuilder {
    static func buildVisualRows(messages: [HomeMessage], currentUserID: Int) -> [ChatRow] {
        var rows: [ChatRow] = []
        rows.reserveCapacity(messages.count + 8)

        for index in messages.indices {
            let message = messages[index]
            if let title = dateSeparatorTitle(messages: messages, index: index) {
                rows.append(ChatRow(id: .separator(title), kind: .separator(title), contentHash: title.hashValue))
            }
            let showsName = shouldShowSenderName(messages: messages, index: index, currentUserID: currentUserID)
            rows.append(ChatRow(
                id: .message(message.id),
                kind: .message(message, showsSenderName: showsName),
                contentHash: messageContentHash(message, showsSenderName: showsName)
            ))
        }
        return rows
    }

    /// Дешёвая сигнатура: только поля, влияющие на вид бабла в ленте.
    /// НЕ хешируем вложенные order/inventory/attachments целиком (их массивы дороги).
    private static func messageContentHash(_ message: HomeMessage, showsSenderName: Bool) -> Int {
        var hasher = Hasher()
        hasher.combine(message.id)
        hasher.combine(message.messageOwnerUserID)
        hasher.combine(message.deliveryState)
        hasher.combine(message.messageType)
        hasher.combine(message.messageText)
        hasher.combine(message.messageStatus)
        hasher.combine(message.messageStatusColor)
        hasher.combine(message.messageOrderID)
        hasher.combine(message.messageInventoryID)
        hasher.combine(message.messageProductRegistrationID)
        hasher.combine(message.order?.comments.count ?? -1)
        hasher.combine(message.attachments.count)
        for attachment in message.attachments {
            hasher.combine(attachment.attachmentID)
        }
        hasher.combine(showsSenderName)
        return hasher.finalize()
    }

    private static func shouldShowSenderName(messages: [HomeMessage], index: Int, currentUserID: Int) -> Bool {
        guard index < messages.count else { return false }
        guard messages[index].messageOwnerUserID != currentUserID else { return false }
        guard index > 0 else { return true }
        return messages[index - 1].messageOwnerUserID != messages[index].messageOwnerUserID
    }

    private static func dateSeparatorTitle(messages: [HomeMessage], index: Int) -> String? {
        guard index < messages.count else { return nil }
        guard let currentDate = messages[index].parsedCreatedAt else { return nil }
        if index > 0,
           let previousDate = messages[index - 1].parsedCreatedAt,
           Calendar.current.isDate(currentDate, inSameDayAs: previousDate) {
            return nil
        }
        return separatorTitle(for: currentDate)
    }

    private static func separatorTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Сегодня"
        }
        if calendar.isDateInYesterday(date) {
            return "Вчера"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return shortDayFormatter.string(from: date)
        }
        return fullDayFormatter.string(from: date)
    }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
}

// MARK: - Живое окружение строки (актуальные колбэки + параметры рендера)

final class ChatRowEnvironment {
    var currentUserID: Int = 0
    var mentionNames: [String] = []
    var highlightedMessageID: Int?
    var highlightRequest: Int = 0

    var unreadOrderCommentsCount: (HomeOrder) -> Int = { _ in 0 }
    var onOpenDocument: (String, Int) -> Void = { _, _ in }
    var onPreviewOrder: (HomeOrder) -> Void = { _ in }
    var onOpenReplySource: (HomeMessage) -> Void = { _ in }
    var onShowMessageActions: (HomeMessage) -> Void = { _ in }
    var onReplyMessage: (HomeMessage) -> Void = { _ in }
    var onEditMessage: (HomeMessage) -> Void = { _ in }
    var onDeleteMessage: (HomeMessage) -> Void = { _ in }
    var onRetryMessage: (HomeMessage) -> Void = { _ in }
    var onOpenAttachment: (HomeMessageAttachment) -> Void = { _ in }
}

// MARK: - SwiftUI-контент ячейки (переиспользует существующие вьюхи)

private struct ChatRowContent: View {
    let kind: ChatRow.Kind
    let mentionNames: [String]
    let currentUserID: Int
    let highlightedMessageID: Int?
    let highlightRequest: Int
    let env: ChatRowEnvironment

    var body: some View {
        switch kind {
        case let .separator(title):
            ChatDateSeparator(title: title)
        case let .message(message, showsSenderName):
            ChatMessageRow(
                message: message,
                isOwnMessage: message.messageOwnerUserID == currentUserID,
                mentionNames: mentionNames,
                isHighlighted: message.id == highlightedMessageID,
                highlightRequest: highlightRequest,
                showsSenderName: showsSenderName,
                unreadOrderCommentsCount: { order in env.unreadOrderCommentsCount(order) },
                onOpenDocument: {
                    if let kind = message.documentKind, let id = message.documentID {
                        env.onOpenDocument(kind, id)
                    }
                },
                onPreviewOrder: { env.onPreviewOrder($0) },
                onOpenReplySource: { env.onOpenReplySource($0) },
                onShowMessageActions: { env.onShowMessageActions($0) },
                onReplyMessage: { env.onReplyMessage($0) },
                onEditMessage: { env.onEditMessage($0) },
                onDeleteMessage: { env.onDeleteMessage($0) },
                onRetryMessage: { env.onRetryMessage($0) },
                onOpenAttachment: { env.onOpenAttachment($0) }
            )
        }
    }
}

// MARK: - Композер (SwiftUI), хостится внутри UIKit и привязан к keyboardLayoutGuide

private struct ChatComposerBar: View {
    @Binding var draft: String
    @Binding var isFocused: Bool
    let inputContext: ChatInputContext?
    let isSending: Bool
    let participants: [ChatParticipant]
    let currentUserID: Int
    let onAttach: () -> Void
    let onCancelInputContext: () -> Void
    let onSend: () -> Void

    @FocusState private var fieldFocused: Bool

    private var mentionSuggestions: [ChatParticipant] {
        guard fieldFocused, let query = MentionEngine.activeQuery(in: draft) else { return [] }
        return MentionEngine.suggestions(from: participants, query: query, excludingUserID: currentUserID)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !mentionSuggestions.isEmpty {
                MentionSuggestionsView(participants: mentionSuggestions) { participant in
                    draft = MentionEngine.insertMention(participant, into: draft)
                    fieldFocused = true
                }
                .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
            }

            ChatInputPanel(
                text: $draft,
                isTextFieldFocused: $fieldFocused,
                inputContext: inputContext,
                isSending: isSending,
                onAttach: onAttach,
                onCancelInputContext: onCancelInputContext,
                onSend: onSend
            )
            .padding(.horizontal, AppTheme.PageLayout.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.background.opacity(0.96))
        .onChange(of: isFocused) { _, newValue in
            if fieldFocused != newValue { fieldFocused = newValue }
        }
        .onChange(of: fieldFocused) { _, newValue in
            if isFocused != newValue { isFocused = newValue }
        }
        .onAppear {
            if fieldFocused != isFocused { fieldFocused = isFocused }
        }
    }
}

// MARK: - UIViewControllerRepresentable

struct ChatConversationView: UIViewControllerRepresentable {
    // Список
    let messages: [HomeMessage]
    let currentUserID: Int
    var mentionNames: [String] = []
    let participants: [ChatParticipant]
    let scrollToBottomRequest: Int
    let scrollToMessageRequest: Int
    let scrollToMessageID: Int?
    let highlightedMessageID: Int?
    let highlightMessageRequest: Int
    let unreadOrderCommentsCount: (HomeOrder) -> Int

    // Колбэки строки
    let onOpenDocument: (String, Int) -> Void
    let onPreviewOrder: (HomeOrder) -> Void
    let onOpenReplySource: (HomeMessage) -> Void
    let onShowMessageActions: (HomeMessage) -> Void
    let onReplyMessage: (HomeMessage) -> Void
    let onEditMessage: (HomeMessage) -> Void
    let onDeleteMessage: (HomeMessage) -> Void
    let onRetryMessage: (HomeMessage) -> Void
    let onOpenAttachment: (HomeMessageAttachment) -> Void
    let onBackgroundTap: () -> Void
    let onPinnedToBottomChange: (Bool) -> Void

    // Композер
    @Binding var draft: String
    @Binding var isInputFocused: Bool
    let inputContext: ChatInputContext?
    let isSending: Bool
    let onAttach: () -> Void
    let onCancelInputContext: () -> Void
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ChatConversationController {
        let controller = ChatConversationController()
        controller.coordinator = context.coordinator
        context.coordinator.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: ChatConversationController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // 1. Обновляем живое окружение строк (актуальные колбэки и параметры).
        let env = controller.rowEnvironment
        env.currentUserID = currentUserID
        env.mentionNames = mentionNames
        env.highlightedMessageID = highlightedMessageID
        env.highlightRequest = highlightMessageRequest
        env.unreadOrderCommentsCount = unreadOrderCommentsCount
        env.onOpenDocument = onOpenDocument
        env.onPreviewOrder = onPreviewOrder
        env.onOpenReplySource = onOpenReplySource
        env.onShowMessageActions = onShowMessageActions
        env.onReplyMessage = onReplyMessage
        env.onEditMessage = onEditMessage
        env.onDeleteMessage = onDeleteMessage
        env.onRetryMessage = onRetryMessage
        env.onOpenAttachment = onOpenAttachment
        controller.onPinnedToBottomChange = onPinnedToBottomChange
        controller.onBackgroundTap = onBackgroundTap

        // 2. Композер.
        controller.updateComposer {
            ChatComposerBar(
                draft: $draft,
                isFocused: $isInputFocused,
                inputContext: inputContext,
                isSending: isSending,
                participants: participants,
                currentUserID: currentUserID,
                onAttach: onAttach,
                onCancelInputContext: onCancelInputContext,
                onSend: onSend
            )
        }

        // 3. Сообщения (применяем только при реальном изменении контента).
        let visualRows = ChatRowBuilder.buildVisualRows(messages: messages, currentUserID: currentUserID)
        controller.applyRowsIfNeeded(
            visualRows,
            messages: messages,
            mentionNames: mentionNames,
            highlightedMessageID: highlightedMessageID,
            highlightRequest: highlightMessageRequest
        )

        // 4. Явные запросы скролла.
        controller.handleScrollRequests(
            scrollToBottomRequest: scrollToBottomRequest,
            scrollToMessageRequest: scrollToMessageRequest,
            scrollToMessageID: scrollToMessageID
        )
    }

    final class Coordinator {
        var parent: ChatConversationView
        weak var controller: ChatConversationController?

        init(_ parent: ChatConversationView) {
            self.parent = parent
        }
    }
}

// MARK: - UIViewController

private nonisolated enum ChatSection: Hashable { case main }

final class ChatConversationController: UIViewController, UICollectionViewDelegate {
    // Зазоры (из-за инверсии оси: inset.top == визуальный НИЗ, inset.bottom == визуальный ВЕРХ).
    private let anchorGap: CGFloat = 14
    private let topGap: CGFloat = 8
    private let anchorThreshold: CGFloat = 44

    let rowEnvironment = ChatRowEnvironment()
    weak var coordinator: ChatConversationView.Coordinator?
    var onPinnedToBottomChange: ((Bool) -> Void)?
    var onBackgroundTap: (() -> Void)?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<ChatSection, ChatRowID>!
    private var composerHost: UIHostingController<AnyView>!
    /// Низ композера: 0 когда клавиатура скрыта (над home-indicator), отрицательный —
    /// поднят на высоту клавиатуры. Анимируем вручную по нотификациям клавиатуры,
    /// чтобы открытие и закрытие шли с ОДНОЙ длительностью и кривой (симметрично).
    private var composerBottomConstraint: NSLayoutConstraint!

    private var rowsByID: [ChatRowID: ChatRow] = [:]
    private var orderedRowIDs: [ChatRowID] = []
    private var lastAggregateHash: Int?

    private var hasPerformedInitialScroll = false
    private var lastReportedPinned: Bool?

    private var lastScrollToBottomRequest = 0
    private var lastScrollToMessageRequest = 0

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        setupCollectionView()
        setupComposer()
        setupConstraints()
        setupDataSource()
        setupGestures()
        registerKeyboardObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasPerformedInitialScroll, !orderedRowIDs.isEmpty, collectionView.bounds.height > 0 {
            scrollToAnchor(animated: false)
            hasPerformedInitialScroll = true
        }
    }

    // MARK: Setup

    private func setupCollectionView() {
        let layout = ChatConversationController.makeLayout(interItemSpacing: 14)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        // Инверсия оси: top == визуальный низ (зазор якоря), bottom == визуальный верх.
        collectionView.contentInset = UIEdgeInsets(top: anchorGap, left: 0, bottom: topGap, right: 0)
        collectionView.verticalScrollIndicatorInsets = collectionView.contentInset
        view.addSubview(collectionView)
    }

    private static func makeLayout(interItemSpacing: CGFloat) -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(60)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = interItemSpacing
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupComposer() {
        composerHost = UIHostingController(rootView: AnyView(EmptyView()))
        composerHost.sizingOptions = .intrinsicContentSize
        composerHost.view.translatesAutoresizingMaskIntoConstraints = false
        composerHost.view.backgroundColor = .clear
        addChild(composerHost)
        view.addSubview(composerHost.view)
        composerHost.didMove(toParent: self)
    }

    private func setupConstraints() {
        composerBottomConstraint = composerHost.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: composerHost.view.topAnchor),

            composerHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottomConstraint
        ])
    }

    // MARK: Клавиатура (симметричная анимация открытия/закрытия)

    private func registerKeyboardObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let endFrameInView = view.convert(endFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - endFrameInView.minY)
        let target = -max(0, overlap - view.safeAreaInsets.bottom)
        animateComposerBottom(to: target, userInfo: userInfo)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        animateComposerBottom(to: 0, userInfo: note.userInfo)
    }

    private func animateComposerBottom(to constant: CGFloat, userInfo: [AnyHashable: Any]?) {
        guard composerBottomConstraint.constant != constant else { return }

        // Системные длительность и кривая клавиатуры — одинаковые для показа и скрытия,
        // поэтому открытие и закрытие получаются симметричными.
        let duration = (userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int)
            ?? Int(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: UInt(curveRaw) << 16)

        let wasAtAnchor = isAtAnchor
        composerBottomConstraint.constant = constant
        UIView.animate(withDuration: duration, delay: 0, options: [options, .beginFromCurrentState]) {
            self.view.layoutIfNeeded()
            if wasAtAnchor {
                self.scrollToAnchor(animated: false)
            }
        }
    }

    private func setupDataSource() {
        let env = rowEnvironment
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, ChatRowID> { [weak self] cell, _, id in
            guard let self, let row = self.rowsByID[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                ChatRowContent(
                    kind: row.kind,
                    mentionNames: env.mentionNames,
                    currentUserID: env.currentUserID,
                    highlightedMessageID: env.highlightedMessageID,
                    highlightRequest: env.highlightRequest,
                    env: env
                )
            }
            .margins(.all, 0)
            cell.backgroundConfiguration = .clear()
            // Переворачиваем ячейку обратно, чтобы контент читался нормально.
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        }

        dataSource = UICollectionViewDiffableDataSource<ChatSection, ChatRowID>(
            collectionView: collectionView
        ) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tap)
    }

    @objc private func handleBackgroundTap() {
        onBackgroundTap?()
    }

    // MARK: Композер

    func updateComposer<Content: View>(@ViewBuilder _ content: () -> Content) {
        composerHost.rootView = AnyView(content())
    }

    // MARK: Применение строк

    func applyRowsIfNeeded(
        _ visualRows: [ChatRow],
        messages: [HomeMessage],
        mentionNames: [String],
        highlightedMessageID: Int?,
        highlightRequest: Int
    ) {
        // Инвертируем: index 0 == новейшее == визуальный низ (точка якоря).
        let inverted = Array(visualRows.reversed())
        let newOrderedIDs = inverted.map(\.id)

        // Быстрая проверка: изменился ли вообще контент.
        let aggregate = aggregateHash(
            inverted: inverted,
            mentionNames: mentionNames,
            highlightedMessageID: highlightedMessageID,
            highlightRequest: highlightRequest
        )
        if aggregate == lastAggregateHash { return }
        lastAggregateHash = aggregate

        // Что переконфигурировать (тот же id, но изменился контент/подсветка/упоминания).
        let mentionChanged = (rowEnvironment.mentionNames != mentionNames)
        var changedIDs: [ChatRowID] = []
        let newRowsByID = Dictionary(inverted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in inverted {
            guard case .message = row.kind else { continue }
            if let old = rowsByID[row.id], case .message = old.kind {
                if old.contentHash != row.contentHash || mentionChanged {
                    changedIDs.append(row.id)
                }
            }
        }
        if let highlightedMessageID {
            let hid = ChatRowID.message(highlightedMessageID)
            if newRowsByID[hid] != nil, !changedIDs.contains(hid) {
                changedIDs.append(hid)
            }
        }

        // Состояние скролла до применения.
        let wasAtAnchor = isAtAnchor
        let previousNewest = newestMessageID(in: orderedRowIDs)
        let oldHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let oldOffsetY = collectionView.contentOffset.y

        rowsByID = newRowsByID
        orderedRowIDs = newOrderedIDs

        var snapshot = NSDiffableDataSourceSnapshot<ChatSection, ChatRowID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(newOrderedIDs, toSection: .main)
        if !changedIDs.isEmpty {
            snapshot.reconfigureItems(changedIDs)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()

        guard hasPerformedInitialScroll else {
            if !orderedRowIDs.isEmpty, collectionView.bounds.height > 0 {
                scrollToAnchor(animated: false)
                hasPerformedInitialScroll = true
            }
            return
        }

        let newNewest = newestMessageID(in: newOrderedIDs)
        if let newNewest, newNewest != previousNewest {
            // Появилось новое новейшее сообщение.
            let isOwn = isOwnMessage(newNewest)
            if isOwn || wasAtAnchor {
                scrollToAnchor(animated: true)
            } else {
                // Чужое и я скроллил вверх — остаюсь на месте.
                let delta = collectionView.collectionViewLayout.collectionViewContentSize.height - oldHeight
                if delta != 0 {
                    collectionView.contentOffset.y = oldOffsetY + delta
                }
            }
        } else {
            // Новейшее не изменилось (правка/доставка/подгрузка старых).
            if wasAtAnchor {
                scrollToAnchor(animated: false)
            }
        }
    }

    // MARK: Явные запросы скролла

    func handleScrollRequests(scrollToBottomRequest: Int, scrollToMessageRequest: Int, scrollToMessageID: Int?) {
        if scrollToBottomRequest != lastScrollToBottomRequest {
            lastScrollToBottomRequest = scrollToBottomRequest
            if hasPerformedInitialScroll {
                scrollToAnchor(animated: true)
            }
        }
        if scrollToMessageRequest != lastScrollToMessageRequest {
            lastScrollToMessageRequest = scrollToMessageRequest
            if let scrollToMessageID {
                scrollToMessage(scrollToMessageID)
            }
        }
    }

    private func scrollToMessage(_ messageID: Int) {
        guard let indexPath = dataSource.indexPath(for: .message(messageID)) else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
    }

    // MARK: Якорь

    private var isAtAnchor: Bool {
        collectionView.contentOffset.y <= -collectionView.contentInset.top + anchorThreshold
    }

    private func scrollToAnchor(animated: Bool) {
        let target = CGPoint(x: 0, y: -collectionView.contentInset.top)
        collectionView.setContentOffset(target, animated: animated)
    }

    private func newestMessageID(in ids: [ChatRowID]) -> Int? {
        for id in ids {
            if case let .message(messageID) = id { return messageID }
        }
        return nil
    }

    private func isOwnMessage(_ messageID: Int) -> Bool {
        guard case let .message(message, _)? = rowsByID[.message(messageID)]?.kind else { return false }
        return message.messageOwnerUserID == rowEnvironment.currentUserID
    }

    private func aggregateHash(
        inverted: [ChatRow],
        mentionNames: [String],
        highlightedMessageID: Int?,
        highlightRequest: Int
    ) -> Int {
        var hasher = Hasher()
        for row in inverted {
            hasher.combine(row.id)
            hasher.combine(row.contentHash)
        }
        hasher.combine(mentionNames)
        hasher.combine(highlightedMessageID)
        hasher.combine(highlightRequest)
        return hasher.finalize()
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pinned = isAtAnchor
        if pinned != lastReportedPinned {
            lastReportedPinned = pinned
            onPinnedToBottomChange?(pinned)
        }
    }
}
