//
//  TombstonePurger.swift
//  PawLog
//
//  墓碑清理：把"已同步 + 超期"的软删除数据物理删除，防止数据库无限膨胀。
//  规则（见 AGENTS 数据规则）：
//  - 只清理 deletedAt 早于保留期（默认 30 天）的墓碑；
//  - 该实体必须存在 ChangeLog 且全部 synced == true；
//  - 当前无同步进行中；
//  - 物理删除顺序遵守引用关系，单次 save。
//

import Foundation
import SwiftData

@MainActor
final class TombstonePurger {
    /// 默认保留天数
    static let defaultRetentionDays = 30
    /// 设置页"自动清理已删除数据"开关的存储键（默认开启）
    static let autoPurgeKey = "settings.autoPurgeTombstones"

    /// 清理结果
    struct Result: Equatable {
        var attachments = 0
        var weightEntries = 0
        var reminders = 0
        var records = 0
        var pets = 0

        var total: Int { attachments + weightEntries + reminders + records + pets }
        static let zero = Result()
    }

    private let context: ModelContext
    private let clock: Clock
    private let calendar: Calendar

    init(context: ModelContext, clock: Clock = SystemClock(), calendar: Calendar = .current) {
        self.context = context
        self.clock = clock
        self.calendar = calendar
    }

    /// 执行一次清理。同步进行中直接返回零，避免删掉正在推送的变更。
    @discardableResult
    func purge(olderThan days: Int = defaultRetentionDays) throws -> Result {
        guard !SyncActivity.isActive else { return .zero }

        let cutoff = calendar.date(byAdding: .day, value: -days, to: clock.now) ?? clock.now
        let synced = try syncStates()

        // 先按当前状态算出候选集，再统一删除，避免边删边查导致关系失效
        let attachments = try context.fetch(FetchDescriptor<Attachment>())
        let purgeableAttachments = attachments.filter {
            isPurgeable($0, kind: .attachment, cutoff: cutoff, synced: synced)
        }
        let attachmentIDs = Set(purgeableAttachments.map(\.id))

        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let purgeableWeights = weights.filter {
            isPurgeable($0, kind: .weightEntry, cutoff: cutoff, synced: synced)
        }
        let weightIDs = Set(purgeableWeights.map(\.id))

        let reminders = try context.fetch(FetchDescriptor<Reminder>())
        let purgeableReminders = reminders.filter {
            isPurgeable($0, kind: .reminder, cutoff: cutoff, synced: synced)
        }
        let reminderIDs = Set(purgeableReminders.map(\.id))

        let records = try context.fetch(FetchDescriptor<Record>())
        let purgeableRecords = records.filter { record in
            guard isPurgeable(record, kind: .record, cutoff: cutoff, synced: synced) else {
                return false
            }
            // 记录下的墓碑附件必须都可清理，否则级联删除会误删未同步数据
            for attachment in record.attachments where attachment.deletedAt != nil {
                if !attachmentIDs.contains(attachment.id) { return false }
            }
            return true
        }
        let recordIDs = Set(purgeableRecords.map(\.id))

        let pets = try context.fetch(FetchDescriptor<Pet>())
        let purgeablePets = pets.filter { pet in
            guard isPurgeable(pet, kind: .pet, cutoff: cutoff, synced: synced) else { return false }
            // 子实体必须都是可清理的墓碑，未同步或未超期的留到下一轮
            for record in pet.records where !recordIDs.contains(record.id) { return false }
            for entry in pet.weightEntries where !weightIDs.contains(entry.id) { return false }
            for reminder in pet.reminders where !reminderIDs.contains(reminder.id) { return false }
            return true
        }

        var result = Result()
        // 物理删除顺序：附件 → 体重 → 提醒 → 记录 → 宠物
        for item in purgeableAttachments {
            context.delete(item)
            result.attachments += 1
        }
        for item in purgeableWeights {
            context.delete(item)
            result.weightEntries += 1
        }
        for item in purgeableReminders {
            context.delete(item)
            result.reminders += 1
        }
        for item in purgeableRecords {
            context.delete(item)
            result.records += 1
        }
        for item in purgeablePets {
            context.delete(item)
            result.pets += 1
        }

        if result.total > 0 { try context.save() }
        return result
    }

    // MARK: - 判定

    /// 每个实体是否"有日志且全部已同步"
    private func syncStates() throws -> [String: Bool] {
        let logs = try context.fetch(FetchDescriptor<ChangeLog>())
        var states: [String: Bool] = [:]
        for log in logs {
            let key = "\(log.entityName)|\(log.entityID.uuidString)"
            states[key] = (states[key] ?? true) && log.synced
        }
        return states
    }

    private func isPurgeable(
        _ object: any SyncTracked,
        kind: SyncEntityKind,
        cutoff: Date,
        synced: [String: Bool]
    ) -> Bool {
        guard let deletedAt = object.deletedAt, deletedAt < cutoff else { return false }
        return synced["\(kind.rawValue)|\(object.id.uuidString)"] == true
    }
}
