//
//  ContentView.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        switch session.screenState {
        case .loading:
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()

                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        case .login:
            LoginView()
        case let .authenticated(user):
            ZStack {
                PageTemplate {
                    HomeView(user: user)
                }

                if session.isProfileOpen {
                    PageTemplate {
                        ProfileEditorView(user: session.currentUser ?? user, store: HomeStore()) {
                            session.closeProfile()
                        } onUserUpdated: { updatedUser in
                            session.updateAuthenticatedUser(updatedUser)
                        }
                    }
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: session.isProfileOpen)
        case let .awaitingApproval(user):
            PageTemplate {
                InactiveAccountView(user: user) {
                    session.showLogin()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSession())
}

