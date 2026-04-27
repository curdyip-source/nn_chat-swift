//
//  AppTheme.swift
//  myclearprojectIOS
//
//  Created by Александр Воробьев on 24.03.2026.
//

import SwiftUI

enum AppTheme {
    static let background = Color.black
    static let titleBackground = Color.black
    static let titleText = Color.white
    static let panelBackground = Color.white.opacity(0.08)
    static let panelStroke = Color.white.opacity(0.10)
    static let mutedText = Color.white.opacity(0.72)
    static let dangerText = Color.red.opacity(0.9)
    static let primaryButtonBackground = Color.white
    static let primaryButtonText = Color.black
    static let secondaryButtonBackground = Color.white.opacity(0.08)
    static let secondaryButtonText = Color.white

    enum PageLayout {
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 18
    }

    enum PageHeader {
        static let titleFont = Font.system(size: 30, weight: .bold, design: .rounded)
        static let subtitleFont = Font.system(size: 16, weight: .medium, design: .rounded)
    }

    enum Auth {
        static let surfaceBackground = Color(red: 0.07, green: 0.07, blue: 0.08)
        static let surfaceStroke = Color.white.opacity(0.08)
        static let surfaceShadow = Color.black.opacity(0.22)
        static let elevatedBackground = Color.white.opacity(0.06)
        static let inputBackground = Color.white.opacity(0.96)
        static let inputText = Color.black.opacity(0.92)
        static let inputPlaceholder = Color.black.opacity(0.58)
        static let largeCornerRadius: CGFloat = 26
        static let mediumCornerRadius: CGFloat = 18
        static let smallCornerRadius: CGFloat = 14
    }
    
    // MARK: - Field (Login Form)
    enum LoginFormField {
        static let width: CGFloat = 260
        static let height: CGFloat = 35
        static let cornerRadius: CGFloat = 18
        static let padding: CGFloat = 10
        static let placeholder = AppTheme.Auth.inputBackground
        static let placeholderText = AppTheme.Auth.inputPlaceholder
    }
    
    enum RegisterFormField {
        static let height: CGFloat = 50
        static let padding: CGFloat = 14
    }
}
