//
//  EmptyState.swift
//  PawLog
//
//  空状态：插图 120、标题 17、说明 15、主按钮宽 200。
//

import SwiftUI

/// 列表页空状态
struct EmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(height: 120)
            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(description)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(buttonTitle, action: action)
                .frame(width: 200)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }
}

#Preview("EmptyState") {
    EmptyState(
        systemImage: "pawprint",
        title: "empty.state.title",
        description: "empty.state.description",
        buttonTitle: "empty.state.action",
        action: {}
    )
    .padding()
    .background(Theme.Palette.background)
}
