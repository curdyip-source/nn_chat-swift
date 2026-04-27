//
//  PageTemplate.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

struct PageTemplate<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                GeneralTitle(topInset: geo.safeAreaInsets.top)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.background)
            .ignoresSafeArea(.container, edges: .all)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
