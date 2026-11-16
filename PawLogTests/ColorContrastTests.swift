//
//  ColorContrastTests.swift
//  PawLogTests
//
//  M11：深色/浅色模式下正文与图表对比度满足 WCAG AA。
//

import XCTest
import SwiftUI
import UIKit
@testable import PawLog

@MainActor
final class ColorContrastTests: XCTestCase {
    func testTextContrastMeetsWCAGAAInBothModes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let background = resolve(Theme.Palette.background, style)
            let card = resolve(Theme.Palette.card, style)
            let primaryText = resolve(Theme.Palette.textPrimary, style)
            let secondaryText = resolve(Theme.Palette.textSecondary, style)
            let tertiaryText = resolve(Theme.Palette.textTertiary, style)

            XCTAssertGreaterThanOrEqual(
                contrast(primaryText, background), 4.5,
                "正文/背景对比度不足（\(style == .dark ? "深色" : "浅色")）"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(primaryText, card), 4.5,
                "正文/卡片对比度不足（\(style == .dark ? "深色" : "浅色")）"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(secondaryText, background), 4.5,
                "次级文字/背景对比度不足（\(style == .dark ? "深色" : "浅色")）"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(tertiaryText, background), 4.5,
                "三级文字/背景对比度不足（\(style == .dark ? "深色" : "浅色")）"
            )
        }
    }

    func testChartGridAndLineMeetWCAGAAInBothModes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let card = resolve(Theme.Palette.card, style)
            let grid = resolve(Theme.Palette.chartGrid, style)
            let line = resolve(Theme.Palette.primary, style)

            XCTAssertGreaterThanOrEqual(
                contrast(grid, card), 3,
                "图表网格/卡片对比度不足（\(style == .dark ? "深色" : "浅色")）"
            )
            XCTAssertGreaterThanOrEqual(
                contrast(line, card), 3,
                "趋势线/卡片对比度不足（\(style == .dark ? "深色" : "浅色")）"
            )
        }
    }

    func testCardAndBackgroundAreDistinctInDarkMode() {
        let background = resolve(Theme.Palette.background, .dark)
        let card = resolve(Theme.Palette.card, .dark)
        XCTAssertNotEqual(background, card, "深色模式下卡片与背景应有层次差异")
        XCTAssertGreaterThan(contrast(card, background), 1.05)
    }

    // MARK: - 工具

    private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> Double {
        let first = luminance(lhs)
        let second = luminance(rhs)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }

        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
