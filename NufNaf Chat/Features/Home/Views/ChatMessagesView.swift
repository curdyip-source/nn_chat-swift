//
//  ChatMessagesView.swift
//  myclearprojectIOS
//  Created by GitHub Copilot on 24.03.2026.
//

import SwiftUI

struct ChatInputContext: Equatable {
    enum Kind: Equatable {
        case reply
        case edit
    }

    let kind: Kind
    let title: String
    let subtitle: String
}

struct ChatMessagesView: View {
    let messages: [HomeMessage]
    let currentUserID: Int
    let scrollToBottomRequest: Int
    let scrollToMessageRequest: Int
    let scrollToMessageID: Int?
    let highlightedMessageID: Int?
    let highlightMessageRequest: Int
    let unreadOrderCommentsCount: (HomeOrder) -> Int
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

    @State private var isPinnedToBottom = true

    private let bottomAnchorID = "chat-bottom-anchor"
    private let bottomMessageInset: CGFloat = 14

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                if let title = dateSeparatorTitle(for: index) {
                                    ChatDateSeparator(title: title)
                                }

                                ChatMessageRow(
                                    message: message,
                                    isOwnMessage: message.messageOwnerUserID == currentUserID,
                                    isHighlighted: message.id == highlightedMessageID,
                                    highlightRequest: highlightMessageRequest,
                                    showsSenderName: shouldShowSenderName(for: index),
                                    unreadOrderCommentsCount: unreadOrderCommentsCount,
                                    onOpenDocument: {
                                        if let kind = message.documentKind, let id = message.documentID {
                                            onOpenDocument(kind, id)
                                        }
                                    },
                                    onPreviewOrder: onPreviewOrder,
                                    onOpenReplySource: onOpenReplySource,
                                    onShowMessageActions: onShowMessageActions,
                                    onReplyMessage: onReplyMessage,
                                    onEditMessage: onEditMessage,
                                    onDeleteMessage: onDeleteMessage,
                                    onRetryMessage: onRetryMessage,
                                    onOpenAttachment: onOpenAttachment
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.top, 14)

                        Color.clear
                            .frame(height: bottomMessageInset)
                            .id(bottomAnchorID)
                            .onAppear {
                                updatePinnedToBottom(true)
                            }
                            .onDisappear {
                                updatePinnedToBottom(false)
                            }
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    onBackgroundTap()
                }
                .onAppear {
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: messages.last?.id) { _, _ in
                    guard let lastMessage = messages.last else { return }
                    if isPinnedToBottom || lastMessage.messageOwnerUserID == currentUserID {
                        scrollToBottom(using: proxy)
                    }
                }
                .onChange(of: scrollToBottomRequest) { _, _ in
                    scrollToBottom(using: proxy)
                }
                .onChange(of: scrollToMessageRequest) { _, _ in
                    guard let scrollToMessageID else { return }
                    scrollToMessage(scrollToMessageID, using: proxy)
                }
            }
        }
    }

    private func updatePinnedToBottom(_ value: Bool) {
        guard isPinnedToBottom != value else { return }
        isPinnedToBottom = value
        onPinnedToBottomChange(value)
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            let action = {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }

            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    action()
                }
            } else {
                action()
            }
        }
    }

    private func scrollToMessage(_ messageID: Int, using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(messageID, anchor: .center)
            }
        }
    }

    private func shouldShowSenderName(for index: Int) -> Bool {
        guard index < messages.count else { return false }
        guard messages[index].messageOwnerUserID != currentUserID else { return false }
        guard index > 0 else { return true }
        return messages[index - 1].messageOwnerUserID != messages[index].messageOwnerUserID
    }

    private func dateSeparatorTitle(for index: Int) -> String? {
        guard index < messages.count else { return nil }
        guard let currentDate = messages[index].parsedCreatedAt else { return nil }
        if index > 0,
           let previousDate = messages[index - 1].parsedCreatedAt,
           Calendar.current.isDate(currentDate, inSameDayAs: previousDate) {
            return nil
        }
        return Self.separatorTitle(for: currentDate)
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

private struct ChatDateSeparator: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

private struct ChatMessageRow: View {
    let message: HomeMessage
    let isOwnMessage: Bool
    let isHighlighted: Bool
    let highlightRequest: Int
    let showsSenderName: Bool
    let unreadOrderCommentsCount: (HomeOrder) -> Int
    let onOpenDocument: () -> Void
    let onPreviewOrder: (HomeOrder) -> Void
    let onOpenReplySource: (HomeMessage) -> Void
    let onShowMessageActions: (HomeMessage) -> Void
    let onReplyMessage: (HomeMessage) -> Void
    let onEditMessage: (HomeMessage) -> Void
    let onDeleteMessage: (HomeMessage) -> Void
    let onRetryMessage: (HomeMessage) -> Void
    let onOpenAttachment: (HomeMessageAttachment) -> Void

    @State private var bubbleBackgroundOpacity = 1.0
    @State private var highlightAnimationRequest = 0

    var body: some View {
        Group {
            if isOwnMessage {
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 32)

                    content
                        .frame(maxWidth: 300, alignment: .trailing)
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    avatar

                    content
                        .frame(maxWidth: 300, alignment: .leading)

                    Spacer(minLength: 20)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: isOwnMessage ? .trailing : .leading)
        .onAppear {
            if isHighlighted {
                triggerHighlightAnimation()
            }
        }
        .onChange(of: isHighlighted) { _, newValue in
            if newValue {
                triggerHighlightAnimation()
            } else {
                bubbleBackgroundOpacity = 1
            }
        }
        .onChange(of: highlightRequest) { _, _ in
            if isHighlighted {
                triggerHighlightAnimation()
            }
        }
    }

    private func triggerHighlightAnimation() {
        highlightAnimationRequest += 1
        let currentRequest = highlightAnimationRequest

        withAnimation(.easeInOut(duration: 0.08)) {
            bubbleBackgroundOpacity = 0.7
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard highlightAnimationRequest == currentRequest else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                bubbleBackgroundOpacity = 1
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
            if let photoURL = AppConfig.mediaURL(for: message.messageOwnerProfilePhoto) {
                AsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(String(message.displayName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else {
                Text(String(message.displayName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private var content: some View {
        VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 6) {
            if showsSenderName {
                Text(message.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
            }

            if let kind = message.documentKind, let id = message.documentID {
                documentCard(kind: kind, id: id)
            } else if !message.attachments.isEmpty {
                attachmentCard
            } else {
                textBubble
            }
        }
    }

    private var textBubble: some View {
        Group {
            if let reply = message.replyFragment {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: {
                        onOpenReplySource(message)
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(replyAccentColor)
                                .frame(width: 3)
                                .clipShape(Capsule())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(reply.author)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(replyForegroundColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                if !reply.message.isEmpty {
                                    Text(reply.message)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(replyForegroundColor.opacity(0.82))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(replyBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !message.visibleMessageText.isEmpty {
                        Text(message.visibleMessageText)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(isOwnMessage ? .black : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, formattedTimestamp.isEmpty ? 14 : 58)
                .padding(.top, 10)
                .padding(.bottom, formattedTimestamp.isEmpty ? 10 : 22)
                .overlay(alignment: .bottomTrailing) {
                    if !formattedTimestamp.isEmpty {
                        deliveryMeta
                            .padding(.trailing, 10)
                            .padding(.bottom, 8)
                    }
                }
            } else {
                Text(message.visibleMessageText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(isOwnMessage ? .black : .white)
                    .padding(.leading, 14)
                    .padding(.trailing, formattedTimestamp.isEmpty ? 14 : 58)
                    .padding(.top, 10)
                    .padding(.bottom, formattedTimestamp.isEmpty ? 10 : 22)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .bottomTrailing) {
                        if !formattedTimestamp.isEmpty {
                            deliveryMeta
                                .padding(.trailing, 10)
                                .padding(.bottom, 8)
                        }
                    }
            }
        }
        .background(textBubbleBackgroundColor.opacity(bubbleBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.35) {
            onShowMessageActions(message)
        }
    }

    private var deliveryMeta: some View {
        HStack(spacing: 6) {
            switch message.deliveryState {
            case .pending:
                ProgressView()
                    .controlSize(.mini)
                    .tint((isOwnMessage ? Color.black : Color.white).opacity(0.58))
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.92))
            case .sent:
                EmptyView()
            }

            if !formattedTimestamp.isEmpty {
                Text(formattedTimestamp)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor((isOwnMessage ? Color.black : Color.white).opacity(0.58))
            }
        }
    }

    private func documentCard(kind: String, id: Int) -> some View {
        let orderUnreadCount = kind == "order" ? message.order.map(unreadOrderCommentsCount) ?? 0 : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(documentTitle(kind: kind))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(documentSubtitle(id: id))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.68))
                }
                Spacer(minLength: 10)

                if let status = message.messageStatus {
                    Text(status)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(statusBadgeForegroundColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(statusBadgeBackgroundColor)
                        .clipShape(Capsule())
                }
            }

            if let text = message.messageText, !text.isEmpty {
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !formattedTimestamp.isEmpty {
                deliveryMeta
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(documentBubbleBackgroundColor.opacity(bubbleBackgroundOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .overlay(alignment: isOwnMessage ? .topLeading : .topTrailing) {
            if orderUnreadCount > 0 {
                Text(orderUnreadCount > 99 ? "99+" : "\(orderUnreadCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color(red: 0.86, green: 0.18, blue: 0.18))
                    .clipShape(Capsule())
                    .offset(x: isOwnMessage ? -6 : 6, y: -6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            guard !message.isLocalOnly else { return }
            onOpenDocument()
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !message.isLocalOnly else { return }
            onShowMessageActions(message)
        }
    }

    private var attachmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(message.attachments, id: \.attachmentID) { attachment in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        attachmentPreview(attachment)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(attachment.attachmentOriginalFilename)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(primaryAttachmentTextColor)
                                .lineLimit(2)

                            Text("\(formattedSize(attachment.attachmentSizeBytes)) - Открыть")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(secondaryAttachmentTextColor)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .center) {
                        Spacer(minLength: 10)

                        if !formattedTimestamp.isEmpty {
                            deliveryMeta
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(attachmentBubbleBackgroundColor.opacity(bubbleBackgroundOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(attachmentBubbleBorderColor, lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture {
                    onOpenAttachment(attachment)
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    onShowMessageActions(message)
                }
            }
        }
    }

    private func attachmentPreview(_ attachment: HomeMessageAttachment) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(attachmentPreviewBackgroundColor)
            .frame(width: 50, height: 50)
            .overlay {
                if attachment.isPhoto {
                    if let mediaURL = attachment.mediaURL {
                        AsyncImage(url: mediaURL) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(attachmentPreviewForegroundColor)
                            default:
                                ProgressView()
                                    .tint(attachmentPreviewForegroundColor)
                            }
                        }
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(attachmentPreviewForegroundColor)
                    }
                } else {
                    Image(systemName: fileIconName(for: attachment))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(attachmentPreviewForegroundColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fileIconName(for attachment: HomeMessageAttachment) -> String {
        if attachment.attachmentMimeType.contains("pdf") {
            return "doc.richtext"
        }
        if attachment.attachmentMimeType.contains("sheet") || attachment.attachmentMimeType.contains("excel") {
            return "tablecells"
        }
        if attachment.attachmentMimeType.contains("word") {
            return "doc.text"
        }
        return "doc"
    }

    private var canReply: Bool {
        message.documentKind == nil && (message.messageType == "message" || !message.attachments.isEmpty)
    }

    private var canEditDelete: Bool {
        message.documentKind == nil && message.attachments.isEmpty && message.messageType == "message" && isOwnMessage
    }

    private var canDelete: Bool {
        message.documentKind == nil && isOwnMessage
    }

    private var replyAccentColor: Color {
        isOwnMessage ? Color.black.opacity(0.7) : Color.white.opacity(0.9)
    }

    private var replyBackgroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }

    private var replyForegroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.72) : Color.white.opacity(0.82)
    }

    private var attachmentBubbleBackgroundColor: Color {
        isOwnMessage ? Color.white : Color(red: 0.18, green: 0.18, blue: 0.21)
    }

    private var textBubbleBackgroundColor: Color {
        isOwnMessage ? Color.white : Color(red: 0.16, green: 0.16, blue: 0.19)
    }

    private var documentBubbleBackgroundColor: Color {
        Color(red: 0.18, green: 0.18, blue: 0.21)
    }

    private var attachmentBubbleBorderColor: Color {
        isOwnMessage ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
    }

    private var primaryAttachmentTextColor: Color {
        isOwnMessage ? Color.black : Color.white
    }

    private var secondaryAttachmentTextColor: Color {
        (isOwnMessage ? Color.black : Color.white).opacity(0.68)
    }

    private var attachmentPreviewBackgroundColor: Color {
        isOwnMessage ? Color.black.opacity(0.06) : Color.white.opacity(0.10)
    }

    private var attachmentPreviewForegroundColor: Color {
        (isOwnMessage ? Color.black : Color.white).opacity(0.8)
    }

    private var formattedTimestamp: String {
        if let date = message.parsedCreatedAt {
            return Self.displayFormatter.string(from: date)
        }
        return message.messageCreatedAt ?? ""
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func documentTitle(kind: String) -> String {
        switch kind {
        case "order":
            return "Заказ"
        case "inventory":
            return "Инвентаризация"
        case "product_registration":
            return "Приемка"
        default:
            return "Документ"
        }
    }

    private func documentSubtitle(id: Int) -> String {
        if message.isLocalOnly {
            switch message.deliveryState {
            case .pending:
                return "Создается..."
            case .failed:
                return "Не отправлено"
            case .sent:
                return "Синхронизация..."
            }
        }
        return "document_id: \(id)"
    }

    private var statusBadgeBackgroundColor: Color {
        switch (message.messageStatusColor ?? "").lowercased() {
        case "green":
            return Color(red: 0.16, green: 0.52, blue: 0.31)
        case "orange":
            return Color(red: 0.78, green: 0.44, blue: 0.12)
        case "blue":
            return Color(red: 0.20, green: 0.40, blue: 0.78)
        default:
            return Color.white.opacity(0.16)
        }
    }

    private var statusBadgeForegroundColor: Color {
        .white
    }

    private func formattedSize(_ bytes: Int?) -> String {
        guard let bytes else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct ChatInputPanel: View {
    @Binding var text: String
    @FocusState.Binding var isTextFieldFocused: Bool
    let inputContext: ChatInputContext?
    let isSending: Bool
    let onAttach: () -> Void
    let onCancelInputContext: () -> Void
    let onSend: () -> Void

    private var inputMinHeight: CGFloat {
        inputContext == nil ? 44 : 72
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: onAttach) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                if let inputContext {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 3, height: 30)
                            .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(inputContext.kind == .edit ? "Редактирование" : "Ответ")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(inputContext.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                            Text(inputContext.subtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Button(action: onCancelInputContext) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Сообщение").foregroundStyle(.white.opacity(0.58)),
                    axis: .vertical
                )
                .focused($isTextFieldFocused)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1 ... 4)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 12)
                .padding(.top, inputContext == nil ? 10 : 2)
                .padding(.bottom, 10)
            }
            .frame(minHeight: inputMinHeight)
            .background(Color.white.opacity(0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onSend) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
        }
    }
}
