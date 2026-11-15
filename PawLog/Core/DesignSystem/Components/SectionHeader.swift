//
//  SectionHeader.swift
//  PawLog
//
//  分组标题：左侧标题 + 右侧可选操作。
//

import SwiftUI

/// 分组标题行
struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("SectionHeader") {
    VStack(spacing: Theme.Spacing.md) {
        SectionHeader(title: "section.header.sample")
        SectionHeader(
            title: "section.header.sample",
            actionTitle: "section.header.action",
            action: {}
        )
    }
    .padding()
    .background(Theme.Palette.background)
}
