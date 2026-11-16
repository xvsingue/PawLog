//
//  WeightTrendView.swift
//  PawLog
//
//  体重趋势：30/90/365 天折线，BCS 胶囊标注，变化提示卡片。
//

import SwiftUI
import SwiftData
import Charts

/// 图表区间
enum WeightRange: Int, CaseIterable, Identifiable {
    case last30 = 30
    case last90 = 90
    case last365 = 365

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .last30: "weight.range.30"
        case .last90: "weight.range.90"
        case .last365: "weight.range.365"
        }
    }
}

struct WeightTrendView: View {
    let pet: Pet
    let service: WeightTrendService
    /// 空状态主按钮：去记录体重
    var onAddRecord: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .forward) private var allEntries: [WeightEntry]
    @State private var range: WeightRange = .last90

    private var entries: [WeightEntry] {
        allEntries.filter { $0.pet?.id == pet.id }
    }

    private var points: [WeightPoint] {
        service.points(from: entries, days: range.rawValue)
    }

    private var alert: WeightAlertKind? {
        service.alert(from: entries)
    }

    var body: some View {
        NavigationStack {
            Group {
                if points.isEmpty {
                    EmptyState(
                        systemImage: "scalemass",
                        title: "weight.trend.empty.title",
                        description: "weight.trend.empty.description",
                        buttonTitle: "weight.trend.empty.action",
                        action: onAddRecord
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .background(Theme.Palette.background)
            .navigationTitle(String(localized: "weight.trend.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }

    // MARK: - 内容

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.groupSpacing) {
                rangePicker

                if let latest = points.last {
                    currentWeight(latest)
                }

                chartCard

                if let alert {
                    alertCard(alert)
                }
            }
            .padding(Theme.Spacing.pageMargin)
        }
    }

    private var rangePicker: some View {
        Picker(String(localized: "weight.trend.range"), selection: $range) {
            ForEach(WeightRange.allCases) { item in
                Text(String(localized: String.LocalizationValue(item.titleKey))).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private func currentWeight(_ point: WeightPoint) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(String(localized: "weight.card.title"))
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(WeightFormatting.string(point.weightKg))
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private var chartCard: some View {
        Card {
            Chart {
                ForEach(points) { point in
                    // 单点数据不画线，只标点
                    if points.count > 1 {
                        LineMark(
                            x: .value("date", point.date),
                            y: .value("weight", point.weightKg)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.Palette.primary)
                    }

                    PointMark(
                        x: .value("date", point.date),
                        y: .value("weight", point.weightKg)
                    )
                    .foregroundStyle(Theme.Palette.primary)
                    .symbolSize(36)
                    .annotation(position: .top, spacing: Theme.Spacing.xs) {
                        if let bcs = point.bcs {
                            bcsBadge(bcs)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.Palette.textTertiary.opacity(0.2))
                    AxisValueLabel(format: .dateTime.month().day())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.Palette.textTertiary.opacity(0.2))
                    AxisValueLabel()
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .frame(height: 220)
        }
    }

    /// Y 轴按数据范围留 15% 余量，避免大片空白
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.weightKg)
        guard let minValue = values.min(), let maxValue = values.max() else { return 0...1 }
        let span = maxValue - minValue
        let padding = max(span * 0.15, 0.2)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private func bcsBadge(_ bcs: Int) -> some View {
        Text(String(localized: "weight.bcs.label \(bcs)"))
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Palette.fill))
    }

    private func alertCard(_ alert: WeightAlertKind) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Palette.accent)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(String(localized: String.LocalizationValue(alert.titleKey)))
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(String(localized: "weight.alert.body"))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("WeightTrendView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
        configurations: config
    )
    let context = container.mainContext
    let pet = Pet(name: "咪咪", species: .cat)
    context.insert(pet)
    let calendar = Calendar.current
    for index in 0..<6 {
        let date = calendar.date(byAdding: .day, value: -index * 10, to: Date())!
        context.insert(WeightEntry(pet: pet, weightKg: 4.0 + Double(index) * 0.05, bcs: 5, date: date))
    }
    try! context.save()
    return WeightTrendView(pet: pet, service: WeightTrendService())
        .modelContainer(container)
}
