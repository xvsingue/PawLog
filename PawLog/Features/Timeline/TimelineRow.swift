//
//  TimelineRow.swift
//  PawLog
//
//  时间线单条记录：类型图标 + 标题 + 摘要 + 时间。
//

import SwiftUI

struct TimelineRow: View {
    let record: Record

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(record.type.tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: record.type.symbolName)
                    .font(.system(size: 16))
                    .foregroundStyle(record.type.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(summary)
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
