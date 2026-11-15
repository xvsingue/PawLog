//
//  Reminder.swift
//  PawLog
//
//  提醒模型。
//

import Foundation
import SwiftData

/// 提醒类型
enum ReminderKind: String, Codable, CaseIterable {
    case vaccine
    case deworming
    case medication
    case visit
    case custom
}

/// 重复规则
enum RepeatRule: String, Codable, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
}

@Model
final class Reminder {
    var id: UUID
    var pet: Pet?
    var kind: ReminderKind
    var sourceRecordID: UUID?
    var dueAt: Date
    var repeatRule: RepeatRule
    var enabled: Bool
    var lastDoneAt: Date?

    init(
        id: UUID = UUID(),
        pet: Pet? = nil,
        kind: ReminderKind,
        sourceRecordID: UUID? = nil,
        dueAt: Date,
        repeatRule: RepeatRule = .none,
        enabled: Bool = true,
        lastDoneAt: Date? = nil
    ) {
        self.id = id
        self.pet = pet
        self.kind = kind
        self.sourceRecordID = sourceRecordID
        self.dueAt = dueAt
        self.repeatRule = repeatRule
        self.enabled = enabled
        self.lastDoneAt = lastDoneAt
    }
}
