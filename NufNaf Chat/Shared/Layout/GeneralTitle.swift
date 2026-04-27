//
//  GeneralTitle.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

struct GeneralTitle: View {
    static let contentHeight: CGFloat = 56

    @EnvironmentObject private var session: AppSession

    let topInset: CGFloat

    private var showsFilterButton: Bool {
        session.currentUser != nil && !session.isProfileOpen && session.activeDocument == nil
    }

    private var isCRMMode: Bool {
        session.chatFilterState.displayMode == .crm
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.titleBackground

            HStack(spacing: 12) {
                if showsFilterButton {
                    Button {
                        session.toggleChatFilterPanel()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(session.isChatFilterPresented ? Color.black : Color.white)
                            .frame(width: 36, height: 36)
                            .background(session.isChatFilterPresented ? Color.white : Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Фильтр")
                } else {
                    Color.clear
                        .frame(width: 36, height: 36)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image("GeneralTitle_Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                        .offset(y: -1)

                    Text("NufNaf")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.titleText)
                }

                Spacer()

                if session.currentUser != nil {
                    Button {
                        if isCRMMode {
                            session.toggleChecklist()
                        } else {
                            session.toggleProfile()
                        }
                    } label: {
                        Image(systemName: isCRMMode ? "checklist" : "person.crop.circle")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle((isCRMMode ? session.isChecklistOpen : session.isProfileOpen) ? Color.black : Color.white)
                            .frame(width: 36, height: 36)
                            .background((isCRMMode ? session.isChecklistOpen : session.isProfileOpen) ? Color.white : Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCRMMode ? "Чек-лист" : "Профиль")
                } else {
                    Color.clear
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: topInset + Self.contentHeight)
        .overlay(alignment: .bottom) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 0.8)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 6)
                .blur(radius: 3)
            }
            .offset(y: 1)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    GeneralTitle(topInset: 0)
        .environmentObject(AppSession())
}
