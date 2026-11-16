//
//  WeightCardView.swift
//  PawLog
//
//  首页体重卡：当前体重、30 天变化、迷你折线。点击进入体重趋势。
//

import SwiftUI
import SwiftData
import Charts

struct WeightCardView: View {
    let pet: Pet
    let service: WeightTrendService
    let onTap: () -> Void

    @Query(sort: \WeightEntry.date, order: .forward) private var allEntries: [WeightEntry]
    @AppStorage(WeightFormatter.storageKey) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit {
        WeightUnit(rawValue: unitRaw) ?? .kg
    }

    private var entries: [WeightEntry] {
        allEntries.filter { $0.pet?.id == pet.id }
    }

    private var latest: WeightPoint? {
        service.latestPoint(from: entries)
    }

    private var change: (delta: Double, percent: Double)? {
        service.recentChange(from: entries)
    }

    private var recentPoints: [WeightPoint] {
        service.points(from: entries, days: WeightTrendService.windowDays * 3)
    }

    var body: some View {
        Button(action: onTap) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text(String(localized: "weight.card.title"))
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }

                    if let latest {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            Text(WeightFormatter.string(latest.weightKg, unit: unit))
                                .font(Theme.Typography.title1)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            if let changeText {
                                Text(changeText)
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                        if recentPoints.count > 1 {
                            sparkline
                        }
                    } else {
                        Text(String(localized: "weight.card.empty"))
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.weightCard")
    }

    private var changeText: String? {
        guard let change else { return nil }
        let sign = change.delta > 0 ? "+" : (change.delta < 0 ? "-" : "")
        let value = WeightFormatter.string(abs(change.delta), unit: unit)
        // 合并为单个参数，保证本地化 key 只有一个 %@
        let signed = sign + value
        return String(localized: "weight.card.change \(signed)")
    }

    private var sparkline: some View {
        Chart(recentPoints) { point in
            LineMark(
                x: .value("date", point.date),
                y: .value("weight", WeightFormatter.value(point.weightKg, in: unit))
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Theme.Palette.primary)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 40)
    }
}

#Preview("WeightCardView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
        configurations: config
    )
    let context = container.mainContext
    let pet = Pet(name: "咪咪", species: .cat)
    context.insert(pet)
    let calendar = Calendar.current
    for index in 0..<5 {
        let date = calendar.date(byAdding: .day, value: -index * 7, to: Date())!
        context.insert(WeightEntry(pet: pet, weightKg: 4.2 - Double(index) * 0.03, bcs: nil, date: date))
    }
    try! context.save()
    return WeightCardView(pet: pet, service: WeightTrendService(), onTap: {})
        .padding()
        .background(Theme.Palette.background)
        .modelContainer(container)
}
