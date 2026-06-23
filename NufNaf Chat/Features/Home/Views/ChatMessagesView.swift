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

struct ChatDateSeparator: View {
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

struct ChatMessageRow: View {
    let message: HomeMessage
    let isOwnMessage: Bool
    var mentionNames: [String] = []
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
    @State private var highlightFlashOpacity = 0.0
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
                highlightFlashOpacity = 0
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

        withAnimation(.easeOut(duration: 0.18)) {
            highlightFlashOpacity = 0.32
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard highlightAnimationRequest == currentRequest else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                highlightFlashOpacity = 0
            }
        }
    }

    /// Accent tint that briefly pulses on top of the bubble when it becomes the
    /// jump target. Reads clearly on light (own), dark (others) and document bubbles,
    /// unlike the previous background-dim which only showed up on light bubbles.
    private var highlightFlashColor: Color {
        Color(red: 0.16, green: 0.50, blue: 0.96)
    }

    @ViewBuilder
    private func highlightFlashOverlay(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(highlightFlashColor.opacity(highlightFlashOpacity))
            .allowsHitTesting(false)
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
                        Text(MentionEngine.attributedText(for: message.visibleMessageText, mentionNames: mentionNames, color: MentionEngine.mentionHighlightColor))
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
                Text(MentionEngine.attributedText(for: message.visibleMessageText, mentionNames: mentionNames, color: MentionEngine.mentionHighlightColor))
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
        .overlay(highlightFlashOverlay(cornerRadius: 20))
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
        let order = kind == "order" ? message.order : nil
        let orderCommentCount = order?.comments.count ?? 0
        let orderUnreadCount = order.map(unreadOrderCommentsCount) ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(documentTitle(kind: kind, id: id))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(documentSubtitle(kind: kind, id: id))
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
        .overlay(highlightFlashOverlay(cornerRadius: 22))
        .overlay(alignment: isOwnMessage ? .topLeading : .topTrailing) {
            if orderCommentCount > 0 {
                Text(orderCommentCount > 99 ? "99+" : "\(orderCommentCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(orderUnreadCount > 0 ? Color(red: 0.86, green: 0.18, blue: 0.18) : Color(red: 0.45, green: 0.47, blue: 0.52))
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
                .overlay(highlightFlashOverlay(cornerRadius: 22))
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

    private func documentTitle(kind: String, id: Int) -> String {
        switch kind {
        case "order":
            return "Заказ №\(id)"
        case "inventory":
            return "Инвентаризация"
        case "product_registration":
            return "Приемка"
        default:
            return "Документ"
        }
    }

    private func documentSubtitle(kind: String, id: Int) -> String {
        if kind == "order" {
            let establishment = orderEstablishmentTitle
            let orderCustomer = orderCustomerTitle

            if !orderCustomer.isEmpty {
                return "\(establishment) * \(orderCustomer)"
            }
            return establishment
        }

        if kind == "inventory" {
            return inventoryEstablishmentTitle
        }

        if kind == "product_registration" {
            let establishment = productRegistrationEstablishmentTitle
            let supplier = productRegistrationSupplierTitle

            if !supplier.isEmpty {
                return "\(establishment) * \(supplier)"
            }
            return establishment
        }

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

    private var orderCustomerTitle: String {
        if let orderCustomer = message.order?.orderCustomer.trimmingCharacters(in: .whitespacesAndNewlines), !orderCustomer.isEmpty {
            return orderCustomer
        }

        guard let messageText = message.messageText else { return "" }
        let firstSegment = messageText
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstSegment
    }

    private var orderEstablishmentTitle: String {
        if let establishment = message.order?.orderEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines), !establishment.isEmpty {
            return establishment
        }
        return "Точка"
    }

    private var inventoryEstablishmentTitle: String {
        if let establishment = message.inventory?.inventoryEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines), !establishment.isEmpty {
            return establishment
        }
        return "Точка"
    }

    private var productRegistrationEstablishmentTitle: String {
        if let establishment = message.productRegistration?.productRegistrationEstablishmentName?.trimmingCharacters(in: .whitespacesAndNewlines), !establishment.isEmpty {
            return establishment
        }
        return "Точка"
    }

    private var productRegistrationSupplierTitle: String {
        if let supplier = message.productRegistration?.productRegistrationSupplier?.trimmingCharacters(in: .whitespacesAndNewlines), !supplier.isEmpty {
            return supplier
        }

        guard let messageText = message.messageText else { return "" }
        let firstSegment = messageText
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstSegment
    }

    private var statusBadgeBackgroundColor: Color {
        BusinessDocumentColors.statusColor(message.messageStatusColor)
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
