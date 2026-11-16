//
//  BackupService.swift
//  PawLog
//
//  全量备份导出与恢复。导出只读，不改动任何数据；导入先完整校验、再在单个
//  save 事务内写入，任一步失败都不留下半份数据。
//

import Foundation
import SwiftData

/// 备份数据集服务
@MainActor
final class BackupService {
    /// 当前支持的文件版本
    static let supportedVersion = "1.0"
    /// 当前 schema 版本
    static let currentSchemaVersion = 1

    let context: ModelContext
    let clock: Clock
    let fileManager: FileManager
    /// 附件恢复目录
    let attachmentDirectory: URL

    init(
        context: ModelContext,
        clock: Clock = SystemClock(),
        fileManager: FileManager = .default,
        attachmentDirectory: URL? = nil
    ) {
        self.context = context
        self.clock = clock
        self.fileManager = fileManager
        self.attachmentDirectory = attachmentDirectory ?? Self.defaultAttachmentDirectory(fileManager: fileManager)
    }

    // MARK: - 导出

    /// 组装备份结构。只读，不修改任何现有数据。
    func makeBackup(now: Date? = nil) throws -> BackupEnvelope {
        let pets = try context.fetch(FetchDescriptor<Pet>())
            .sorted { $0.sortIndex != $1.sortIndex ? $0.sortIndex < $1.sortIndex : $0.id.uuidString < $1.id.uuidString }
        let records = try context.fetch(FetchDescriptor<Record>())
            .sorted { $0.occurredAt != $1.occurredAt ? $0.occurredAt < $1.occurredAt : $0.id.uuidString < $1.id.uuidString }
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
        let reminders = try context.fetch(FetchDescriptor<Reminder>())
            .sorted { $0.dueAt != $1.dueAt ? $0.dueAt < $1.dueAt : $0.id.uuidString < $1.id.uuidString }
        let attachments = try context.fetch(FetchDescriptor<Attachment>())
            .sorted { $0.id.uuidString < $1.id.uuidString }

        return BackupEnvelope(
            version: Self.supportedVersion,
            schemaVersion: Self.currentSchemaVersion,
            exportedAt: now ?? clock.now,
            counts: BackupCounts(
                pets: pets.count,
                records: records.count,
                weightEntries: weights.count,
                reminders: reminders.count,
                attachments: attachments.count
            ),
            pets: pets.map(Self.petDTO),
            records: records.map(Self.recordDTO),
            weightEntries: weights.map(Self.weightDTO),
            reminders: reminders.map(Self.reminderDTO),
            attachments: attachments.map { Self.attachmentDTO($0, fileManager: fileManager) }
        )
    }

    /// 编码为 JSON 数据
    func exportData(now: Date? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(try makeBackup(now: now))
    }

    /// 写入临时目录，返回可分享的文件 URL
    func writeTemporaryBackup(now: Date? = nil) throws -> URL {
        let date = now ?? clock.now
        let url = fileManager.temporaryDirectory.appendingPathComponent(Self.fileName(for: date))
        try exportData(now: date).write(to: url, options: .atomic)
        return url
    }

    /// 文件名 pawlog-backup-yyyyMMdd-HHmm.json
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
        return "pawlog-backup-\(stamp).json"
    }

    // MARK: - 导入

    /// 本地各模型条数
    func existingCounts() throws -> BackupCounts {
        BackupCounts(
            pets: try context.fetchCount(FetchDescriptor<Pet>()),
            records: try context.fetchCount(FetchDescriptor<Record>()),
            weightEntries: try context.fetchCount(FetchDescriptor<WeightEntry>()),
            reminders: try context.fetchCount(FetchDescriptor<Reminder>()),
            attachments: try context.fetchCount(FetchDescriptor<Attachment>())
        )
    }

    /// 解析并校验备份文件，不触碰本地数据
    func decode(_ data: Data) throws -> BackupEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.malformed(reason: String(localized: "settings.backup.error.unreadable"))
        }
        try validate(envelope)
        return envelope
    }

    /// 导入备份。先完整校验；本地已有数据时必须显式确认覆盖。
    @discardableResult
    func importBackup(_ data: Data, overwriteConfirmed: Bool = false) throws -> BackupCounts {
        let envelope = try decode(data)

        let existing = try existingCounts().records
        if existing > 0 && !overwriteConfirmed {
            throw BackupError.overwriteNotConfirmed(existingRecords: existing)
        }

        // 删除与写入在同一次 save 中完成；任一步失败则整体回滚，不留半份数据
        do {
            try deleteAll()
            try insert(envelope)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return envelope.counts
    }

    /// 逐个删除全部业务数据。不删除 Entitlement，避免抹掉本地购买状态。
    private func deleteAll() throws {
        for record in try context.fetch(FetchDescriptor<Record>()) { context.delete(record) }
        for entry in try context.fetch(FetchDescriptor<WeightEntry>()) { context.delete(entry) }
        for reminder in try context.fetch(FetchDescriptor<Reminder>()) { context.delete(reminder) }
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) { context.delete(attachment) }
        for pet in try context.fetch(FetchDescriptor<Pet>()) { context.delete(pet) }
    }

    private static func defaultAttachmentDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Attachments", isDirectory: true)
    }
}
