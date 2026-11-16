//
//  WeightFormatter.swift
//  PawLog
//
//  体重单位与格式化：全项目唯一的体重换算/展示入口。
//

import Foundation

/// 体重单位
enum WeightUnit: String, CaseIterable, Identifiable {
    case kg
    case lb

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .kg: "settings.unit.kg"
        case .lb: "settings.unit.lb"
        }
    }

    /// 单位符号（kg / lb，跨语言一致）
    var symbol: String { rawValue }
}

/// 体重格式化与校验
enum WeightFormatter {
    /// 单位偏好存储 key
    static let storageKey = "settings.weightUnit"

    /// 允许的体重区间（kg）
    static let minKilograms = 0.2
    static let maxKilograms = 120.0

    private static let poundsPerKilogram = 2.204_622_621_8

    /// 当前单位（持久化）
    static var unit: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .kg
    }

    static func setUnit(_ unit: WeightUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: storageKey)
    }

    /// 存储值（kg）→ 展示值
    static func value(_ kilograms: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kg: kilograms
        case .lb: kilograms * poundsPerKilogram
        }
    }

    /// 展示值 → 存储值（kg）
    static func kilograms(_ value: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kg: value
        case .lb: value / poundsPerKilogram
        }
    }

    /// 按指定单位格式化，如「4.2 kg」「9.3 lb」
    /// 单位符号固定为 kg / lb（系统单位名会本地化成「磅」，不符合本产品文案）
    static func string(_ kilograms: Double, unit: WeightUnit = unit) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        let converted = value(kilograms, in: unit)
        let number = formatter.string(from: NSNumber(value: converted)) ?? "\(converted)"
        return "\(number) \(unit.symbol)"
    }

    /// 双单位提示，如「4.2 kg / 9.3 lb」
    static func dualString(_ kilograms: Double) -> String {
        "\(string(kilograms, unit: .kg)) / \(string(kilograms, unit: .lb))"
    }

    /// 是否落在允许区间内（kg）
    static func isWithinRange(_ kilograms: Double) -> Bool {
        kilograms >= minKilograms && kilograms <= maxKilograms
    }
}

/// 理想体重 ±10% 目标带
enum IdealWeightBand {
    /// 目标带相对理想体重的比例
    static let ratio = 0.10

    /// 目标带上下界（展示单位），用于图表浅色带
    static func bounds(idealKilograms: Double, unit: WeightUnit) -> ClosedRange<Double> {
        let lower = WeightFormatter.value(idealKilograms * (1 - ratio), in: unit)
        let upper = WeightFormatter.value(idealKilograms * (1 + ratio), in: unit)
        return lower...upper
    }
}
