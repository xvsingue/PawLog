//
//  Chip.swift
//  PawLog
//
//  标签胶囊：高 28，选中时 12% 主色底。
//

import SwiftUI

/// 标签胶囊
struct Chip: View {
    let title: LocalizedStringKey
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(Theme.Typography.footnote)
            .foregroundStyle(isSelected ? Theme.Palette.primary : Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(isSelected ? Theme.Palette.primary.opacity(0.12) : Theme.Palette.fill)
            )
    }
}

#Preview("Chip") {
    HStack(spacing: Theme.Spacing.sm) {
        Chip(title: "chip.sample.selected", isSelected: true)
        Chip(title: "chip.sample.normal", isSelected: false)
    }
    .padding()
    .background(Theme.Palette.background)
}
