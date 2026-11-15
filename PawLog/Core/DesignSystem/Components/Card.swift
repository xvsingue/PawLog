//
//  Card.swift
//  PawLog
//
//  卡片：白底、圆角 16、阴影 0 1 2 黑 6%。
//

import SwiftUI

/// 通用卡片容器
struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Theme.Spacing.cardPadding)
            .background(Theme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

#Preview("Card") {
    Card {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("card.sample.title")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("card.sample.subtitle")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
    .padding()
    .background(Theme.Palette.background)
}
