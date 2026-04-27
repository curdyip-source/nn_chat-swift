//
//  DocumentPlaceholderView.swift
//  myclearprojectIOS
//
//  Created by GitHub Copilot on 24.03.2026.
//

import SwiftUI

struct DocumentPlaceholderView: View {
    let destination: AppDocumentDestination
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(documentTitle)
                .font(AppTheme.PageHeader.titleFont)
                .foregroundStyle(.white)

            Text("document_id: \(destination.id)")
                .font(AppTheme.PageHeader.subtitleFont)
                .foregroundStyle(AppTheme.mutedText)

            Spacer()

            Button(action: onClose) {
                Text("Закрыть")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var documentTitle: String {
        switch destination.kind {
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
}
