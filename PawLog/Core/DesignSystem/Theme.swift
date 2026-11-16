//
//  Theme.swift
//  PawLog
//
//  设计系统唯一来源：颜色、字号、间距、圆角。
//  禁止在页面内写死色值、字号、间距或圆角。
//

import SwiftUI

/// 设计系统根命名空间。调用方式：Theme.Palette.primary / Theme.Spacing.md 等。
enum Theme {
    /// 颜色令牌，深浅自适应
    enum Palette {
        static let primary = Color.dynamic(light: Color(hex: "3D7A63"), dark: Color(hex: "5FA98A"))
        /// 到期 / 预警 / 试用专用色
        static let accent = Color(hex: "E08A54")
        static let background = Color.dynamic(light: Color(hex: "F7F5F1"), dark: Color(hex: "121212"))
        static let card = Color.dynamic(light: Color(hex: "FFFFFF"), dark: Color(hex: "1C1C1E"))
        static let fill = Color.dynamic(light: Color(hex: "F2F0EC"), dark: Color(hex: "2C2C2E"))
        static let textPrimary = Color.dynamic(light: Color(hex: "1C1C1E"), dark: Color(hex: "FFFFFF"))
        static let textSecondary = Color.dynamic(light: Color(hex: "6B6B70"), dark: Color(hex: "8E8E93"))
        static let textTertiary = Color.dynamic(light: Color(hex: "6F6F75"), dark: Color(hex: "8E8E93"))
        /// 图表网格线：对卡片背景保持 ≥3:1（WCAG AA 大图形）
        static let chartGrid = Color.dynamic(light: Color(hex: "8A8A8F"), dark: Color(hex: "8E8E93"))
        static let danger = Color(hex: "C94F45")
    }

    /// 间距令牌
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        /// 页面左右边距
        static let pageMargin: CGFloat = 20
        /// 卡片内边距
        static let cardPadding: CGFloat = 16
        /// 列表行高
        static let listRowHeight: CGFloat = 52
        /// 分组间距
        static let groupSpacing: CGFloat = 24
    }

    /// 圆角令牌
    enum Radius {
        static let card: CGFloat = 16
        static let button: CGFloat = 14
        static let input: CGFloat = 12
        static let pill: CGFloat = 999
    }

    /// 字号令牌。使用系统文本样式而非固定字号，随 Dynamic Type 一起缩放。
    enum Typography {
        static let largeTitle = Font.system(.largeTitle, weight: .bold)
        static let title1 = Font.system(.title, weight: .semibold)
        static let title2 = Font.system(.title2, weight: .semibold)
        static let title3 = Font.system(.headline, weight: .semibold)
        static let body = Font.system(.body)
        static let callout = Font.system(.callout)
        static let footnote = Font.system(.footnote)
        static let caption = Font.system(.caption)
        /// 等宽数字，用于体重、金额等数字展示
        static let monospacedDigit = Font.system(.body).monospacedDigit()
    }
}
