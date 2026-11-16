//
//  TimelineRow.swift
//  PawLog
//
//  时间线单条记录：类型图标 + 标题 + 摘要 + 时间。
//

import SwiftUI

struct TimelineRow: View {
    let record: Record
    /// 免费用户超出历史窗口的记录：锁定态，数据仍保留
    var isLocked: Bool = false

    @AppStorage(WeightFormatter.storageKey) private var unitRaw = WeightUnit.kg.rawValue

    private var unit: WeightUnit {
        WeightUnit(rawValue: unitRaw) ?? .kg
    }

    /// 体重记录按当前单位实时换算，避免沿用保存时的标题
    private var displayTitle: String {
        if record.type == .weight, let payload = record.payload(WeightPayload.self) {
            return WeightFormatter.string(payload.weightKg, unit: unit)
        }
        return record.title
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill((isLocked ? Theme.Palette.textTertiary : record.type.tint).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: isLocked ? "lock.fill" : record.type.symbolName)
                    .font(.system(size: 16))
                    .foregroundStyle(isLocked ? Theme.Palette.textTertiary : record.type.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isLocked ? String(localized: "timeline.locked.title") : displayTitle)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(isLocked ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(isLocked ? String(localized: "timeline.locked.action") : summary)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(record.occurredAt.formatted(date: .omitted, time: .shortened))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(minHeight: 44)
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    /// 摘要：类型名首位，避免未知类型空白
    private var summary: String {
        let typeName = record.type.localizedTitle
        if let note = record.note, !note.isEmpty {
            return "\(typeName) · \(note)"
        }
        return typeName
    }
}

#Preview("TimelineRow") {
    let pet = Pet(name: "咪咪", species: .cat)
    let record = Record(type: .vaccine, occurredAt: Date(), title: "猫三联")
    record.pet = pet
    return TimelineRow(record: record)
        .padding()
        .background(Theme.Palette.background)
}
