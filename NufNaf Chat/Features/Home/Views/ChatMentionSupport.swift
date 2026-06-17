//
//  ChatMentionSupport.swift
//  NufNaf Chat
//
//  Reusable @-mention detection, insertion and suggestion UI for chat inputs.
//

import SwiftUI

enum MentionEngine {
    static let trigger: Character = "@"

    /// Returns the query the user is currently typing after a trailing "@" (no whitespace yet),
    /// or nil when no mention is being composed at the end of the text.
    static func activeQuery(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: trigger) else { return nil }

        let afterTrigger = text[text.index(after: atIndex)...]
        if afterTrigger.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            return nil
        }

        if atIndex > text.startIndex {
            let previous = text[text.index(before: atIndex)]
            if !previous.isWhitespace && !previous.isNewline {
                return nil
            }
        }

        return String(afterTrigger)
    }

    static func suggestions(from participants: [ChatParticipant], query: String, excludingUserID: Int?, limit: Int = 50) -> [ChatParticipant] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = participants.filter { $0.id != excludingUserID }

        let matched: [ChatParticipant]
        if normalizedQuery.isEmpty {
            matched = pool
        } else {
            matched = pool.filter { participant in
                participant.userFirstName.lowercased().contains(normalizedQuery)
                    || participant.userSecondName.lowercased().contains(normalizedQuery)
                    || participant.displayName.lowercased().contains(normalizedQuery)
                    || participant.userLogin.lowercased().contains(normalizedQuery)
            }
        }

        return Array(matched.prefix(limit))
    }

    /// Replaces the trailing "@query" with "@DisplayName " and returns the new text.
    static func insertMention(_ participant: ChatParticipant, into text: String) -> String {
        guard let atIndex = text.lastIndex(of: trigger) else {
            return text + String(trigger) + participant.displayName + " "
        }
        let prefix = String(text[..<atIndex])
        return prefix + String(trigger) + participant.displayName + " "
    }

    /// Resolves which participants are actually mentioned in the final text (token-boundary aware).
    static func mentionedUserIDs(in text: String, participants: [ChatParticipant]) -> [Int] {
        var ids = Set<Int>()
        for participant in participants where containsMentionToken(text, token: String(trigger) + participant.displayName) {
            ids.insert(participant.id)
        }
        return Array(ids)
    }

    /// Returns the message text with "@DisplayName" mention tokens tinted in the accent color.
    static func attributedText(for text: String, mentionNames: [String], color: Color) -> AttributedString {
        var attributed = AttributedString(text)
        let names = mentionNames.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !names.isEmpty else { return attributed }

        for name in names {
            let token = String(trigger) + name
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: token) {
                let afterIndex = range.upperBound
                let isBoundary: Bool
                if afterIndex == attributed.endIndex {
                    isBoundary = true
                } else {
                    let nextCharacter = attributed.characters[afterIndex]
                    isBoundary = !nextCharacter.isLetter && !nextCharacter.isNumber
                }
                if isBoundary {
                    attributed[range].foregroundColor = color
                }
                searchStart = range.upperBound
            }
        }

        return attributed
    }

    static let mentionHighlightColor = Color(red: 0.16, green: 0.50, blue: 0.96)

    private static func containsMentionToken(_ text: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: token, range: searchRange) {
            let afterIndex = range.upperBound
            if afterIndex == text.endIndex {
                return true
            }
            let nextCharacter = text[afterIndex]
            if !nextCharacter.isLetter && !nextCharacter.isNumber {
                return true
            }
            searchRange = afterIndex..<text.endIndex
        }
        return false
    }
}

struct MentionSuggestionsView: View {
    let participants: [ChatParticipant]
    let onSelect: (ChatParticipant) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(participants) { participant in
                        Button {
                            onSelect(participant)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 32, height: 32)
                                    Text(String(participant.displayName.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(participant.displayName)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text("@\(participant.userLogin)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.55))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if participant.id != participants.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
