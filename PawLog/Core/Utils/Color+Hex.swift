//
//  Color+Hex.swift
//  PawLog
//
//  全项目唯一允许使用 UIKit 的文件：用于构造深浅自适应动态色。
//  其余文件禁止 import UIKit。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// 从十六进制字符串初始化颜色，支持 #RGB / #RRGGBB / #RRGGBBAA
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch sanitized.count {
        case 3: // RGB
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RRGGBB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RRGGBBAA
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// 深浅自适应动态色：浅色模式用 light，深色模式用 dark。
    static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        return light
        #endif
    }
}
