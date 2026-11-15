//
//  PrimaryButton.swift
//  PawLog
//
//  主按钮：主色填充、白字 17 Semibold、高 52、圆角 14；按下 scale 0.98。
//

import SwiftUI

/// 主按钮样式
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.title3)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Palette.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 主按钮视图
struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

#Preview("PrimaryButton") {
    VStack(spacing: Theme.Spacing.lg) {
        PrimaryButton("button.primary.confirm") {}
        PrimaryButton("button.primary.save") {}
    }
    .padding()
    .background(Theme.Palette.background)
}
