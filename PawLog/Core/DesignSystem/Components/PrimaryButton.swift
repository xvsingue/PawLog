//
//  PrimaryButton.swift
//  PawLog
//
//  主按钮：主色填充、白字 17 Semibold、高 52、圆角 14；按下 scale 0.98。
//

import SwiftUI

/// 主按钮样式
struct PrimaryButtonStyle: ButtonStyle {
    var reduceMotion: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.title3)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Palette.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            // 减弱动态效果时取消缩放，仅用透明度提示按压
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1.0))
            .opacity(reduceMotion && configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 主按钮视图
struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle(reduceMotion: reduceMotion))
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
