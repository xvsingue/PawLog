//
//  ActiveQueries.swift
//  PawLog
//
//  查询层的统一墓碑过滤入口。所有 @Query 与 FetchDescriptor 都必须使用这里
//  的谓词，避免"已删除数据"重新出现在列表、统计或导出中。
//

import Foundation
import SwiftData

/// 活跃数据谓词（排除墓碑）
enum ActivePredicates {
    static var pets: Predicate<Pet> {
        #Predicate<Pet> { $0.deletedAt == nil }
    }

    static var records: Predicate<Record> {
        #Predicate<Record> { $0.deletedAt == nil }
    }

    static var weightEntries: Predicate<WeightEntry> {
        #Predicate<WeightEntry> { $0.deletedAt == nil }
    }

    static var reminders: Predicate<Reminder> {
        #Predicate<Reminder> { $0.deletedAt == nil }
    }

    static var attachments: Predicate<Attachment> {
        #Predicate<Attachment> { $0.deletedAt == nil }
    }
}
