//
//  TimelineGrouping.swift
//  PawLog
//
//  时间线分组：月 → 日，倒序。
//

import Foundation

/// 一天的分组
struct TimelineDay: Identifiable {
    let id: Date
    let title: String
    let records: [Record]
}

/// 一个月的分组
struct TimelineMonth: Identifiable {
    let id: Date
    let title: String
    let days: [TimelineDay]
}

enum TimelineGrouping {
    /// 把记录组装为 月 → 日 的倒序结构
    static func group(_ records: [Record], calendar: Calendar = .current) -> [TimelineMonth] {
        let sorted = records.sorted { $0.occurredAt > $1.occurredAt }

        var dayBuckets: [Date: [Record]] = [:]
        for record in sorted {
            let day = calendar.startOfDay(for: record.occurredAt)
            dayBuckets[day, default: []].append(record)
        }

        let days = dayBuckets.keys.sorted(by: >).map { day in
            TimelineDay(
                id: day,
                title: day.formatted(.dateTime.month().day()),
                records: dayBuckets[day] ?? []
            )
        }

        var monthBuckets: [Date: [TimelineDay]] = [:]
        for day in days {
            let comps = calendar.dateComponents([.year, .month], from: day.id)
            let monthStart = calendar.date(from: comps) ?? day.id
            monthBuckets[monthStart, default: []].append(day)
        }

        return monthBuckets.keys.sorted(by: >).map { month in
            TimelineMonth(
                id: month,
                title: month.formatted(.dateTime.year().month(.wide)),
                days: monthBuckets[month] ?? []
            )
        }
    }

    /// 同一天最多直接展示的条数
    static let collapsedLimit = 3
}
