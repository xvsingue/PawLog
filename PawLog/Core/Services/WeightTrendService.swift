//
//  WeightTrendService.swift
//  PawLog
//
//  体重趋势：区间取点、30 天变化提示。提示文案保持中性，不含任何疾病名称。
//

import Foundation
import SwiftData

/// 体重曲线上的一个点
struct WeightPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let weightKg: Double
    let bcs: Int?
}

/// 体重变化提示类型
enum WeightAlertKind: Equatable {
    /// 30 天内首末变化达到 5% 阈值
    case rapidChange(isRising: Bool, percent: Double)
    /// 最近连续 3 次记录同向
    case consecutive(isRising: Bool)
}

/// 体重趋势服务
@MainActor
final class WeightTrendService {
    /// 触发提示的变化阈值（5%，含边界）
    static let rapidChangeThreshold = 0.05
    /// 触发提示所需的最少记录数
    static let minimumPointCount = 3
    /// 变化判定固定窗口（天）
    static let windowDays = 30

    private let calendar: Calendar
    private let clock: Clock

    init(calendar: Calendar = .current, clock: Clock = SystemClock()) {
        self.calendar = calendar
        self.clock = clock
    }

    // MARK: - 取点

    /// 指定区间内的体重点：同日取最后一条，按日期升序
    func points(from entries: [WeightEntry], days: Int) -> [WeightPoint] {
        let startOfToday = calendar.startOfDay(for: clock.now)
        let cutoff = calendar.date(byAdding: .day, value: -days, to: startOfToday) ?? .distantPast
        return Self.dailyLastEntries(entries, calendar: calendar)
            .filter { $0.date >= cutoff }
    }

    /// 指定区间内的体重点（按宠物关系取）
    func points(for pet: Pet, days: Int) -> [WeightPoint] {
        points(from: pet.weightEntries, days: days)
    }

    /// 最新一条体重（不受区间限制）
    func latestPoint(from entries: [WeightEntry]) -> WeightPoint? {
        Self.dailyLastEntries(entries, calendar: calendar).last
    }

    /// 最新一条体重（按宠物关系取）
    func latestPoint(for pet: Pet) -> WeightPoint? {
        latestPoint(from: pet.weightEntries)
    }

    /// 最近 30 天变化：返回较窗口首条的变化量与比例，不足两条返回 nil
    func recentChange(from entries: [WeightEntry]) -> (delta: Double, percent: Double)? {
        let window = points(from: entries, days: Self.windowDays)
        guard window.count >= 2,
              let first = window.first,
              let last = window.last,
              first.weightKg > 0 else { return nil }
        let delta = last.weightKg - first.weightKg
        return (delta, delta / first.weightKg)
    }

    /// 最近 30 天变化（按宠物关系取）
    func recentChange(for pet: Pet) -> (delta: Double, percent: Double)? {
        recentChange(from: pet.weightEntries)
    }

    // MARK: - 提示

    /// 变化提示。固定使用最近 30 天数据，不随图表所选区间变化
    func alert(from entries: [WeightEntry]) -> WeightAlertKind? {
        Self.analyze(points(from: entries, days: Self.windowDays))
    }

    /// 变化提示（按宠物关系取）
    func alert(for pet: Pet) -> WeightAlertKind? {
        alert(from: pet.weightEntries)
    }

    /// 判定规则（纯函数，便于测试）
    static func analyze(_ points: [WeightPoint]) -> WeightAlertKind? {
        guard points.count >= minimumPointCount,
              let first = points.first,
              let last = points.last,
              first.weightKg > 0 else { return nil }

        // 规则一：窗口内首末变化达到 5%（含边界）
        let change = (last.weightKg - first.weightKg) / first.weightKg
        if abs(change) >= rapidChangeThreshold {
            return .rapidChange(isRising: change > 0, percent: abs(change))
        }

        // 规则二：最近 3 次记录相邻比较同向
        let recent = Array(points.suffix(3))
        let deltas = zip(recent, recent.dropFirst()).map { $1.weightKg - $0.weightKg }
        if deltas.allSatisfy({ $0 > 0 }) { return .consecutive(isRising: true) }
        if deltas.allSatisfy({ $0 < 0 }) { return .consecutive(isRising: false) }
        return nil
    }

    // MARK: - 去重

    /// 按自然日去重：同日取时间最晚的一条，结果按时间升序
    private static func dailyLastEntries(_ entries: [WeightEntry], calendar: Calendar) -> [WeightPoint] {
        var latestByDay: [Date: WeightEntry] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = latestByDay[day], existing.date >= entry.date { continue }
            latestByDay[day] = entry
        }
        return latestByDay.values
            .sorted { $0.date < $1.date }
            .map { WeightPoint(id: $0.id, date: $0.date, weightKg: $0.weightKg, bcs: $0.bcs) }
    }
}

// MARK: - 展示文案

extension WeightAlertKind {
    /// 提示标题 key（中性表述，不含疾病名）
    var titleKey: String {
        switch self {
        case .rapidChange(let isRising, _):
            isRising ? "weight.alert.rapid.up" : "weight.alert.rapid.down"
        case .consecutive(let isRising):
            isRising ? "weight.alert.consecutive.up" : "weight.alert.consecutive.down"
        }
    }
}
