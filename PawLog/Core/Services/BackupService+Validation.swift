//
//  BackupService+Validation.swift
//  PawLog
//
//  备份文件校验：版本、条数、枚举取值、关系引用、base64 合法性。
//

import Foundation

extension BackupService {
    /// 校验版本、结构与引用完整性
    func validate(_ envelope: BackupEnvelope) throws {
        let fileVersion = try Self.parseVersion(envelope.version)
        let supported = try Self.parseVersion(Self.supportedVersion)

        if fileVersion > supported {
            throw BackupError.versionTooNew(file: envelope.version, supported: Self.supportedVersion)
        }
        if fileVersion < supported {
            throw BackupError.versionTooOld(file: envelope.version, supported: Self.supportedVersion)
        }
        guard envelope.schemaVersion == Self.currentSchemaVersion else {
            throw BackupError.schemaVersionMismatch(
                file: envelope.schemaVersion,
                supported: Self.currentSchemaVersion
            )
        }

        let actual = BackupCounts(
            pets: envelope.pets.count,
            records: envelope.records.count,
            weightEntries: envelope.weightEntries.count,
            reminders: envelope.reminders.count,
            attachments: envelope.attachments.count
        )
        guard actual == envelope.counts else {
            throw BackupError.malformed(reason: String(localized: "settings.backup.error.countMismatch"))
        }

        let petIDs = Set(envelope.pets.map(\.id))
        let recordIDs = Set(envelope.records.map(\.id))

        for pet in envelope.pets {
            try require(PetSpecies(rawValue: pet.species) != nil, "pet.species")
            try require(PetSex(rawValue: pet.sex) != nil, "pet.sex")
            _ = try Self.decodeBase64(pet.avatarDataBase64, field: "pet.avatarData")
        }
        for record in envelope.records {
            try require(RecordType(rawValue: record.type) != nil, "record.type")
            try require(record.petID.map(petIDs.contains) ?? true, "record.petID")
        }
        for weight in envelope.weightEntries {
            try require(weight.petID.map(petIDs.contains) ?? true, "weightEntry.petID")
            try require(weight.recordID.map(recordIDs.contains) ?? true, "weightEntry.recordID")
        }
        for reminder in envelope.reminders {
            try require(ReminderKind(rawValue: reminder.kind) != nil, "reminder.kind")
            try require(RepeatRule(rawValue: reminder.repeatRule) != nil, "reminder.repeatRule")
            try require(reminder.petID.map(petIDs.contains) ?? true, "reminder.petID")
        }
        for attachment in envelope.attachments {
            try require(AttachmentKind(rawValue: attachment.kind) != nil, "attachment.kind")
            try require(attachment.recordID.map(recordIDs.contains) ?? true, "attachment.recordID")
            _ = try Self.decodeBase64(attachment.fileDataBase64, field: "attachment.file")
            _ = try Self.decodeBase64(attachment.thumbnailDataBase64, field: "attachment.thumbnail")
        }
    }

    // MARK: - 工具

    func require(_ condition: Bool, _ field: String) throws {
        guard condition else {
            throw BackupError.malformed(reason: field)
        }
    }

    func requireSpecies(_ raw: String) throws -> PetSpecies {
        guard let value = PetSpecies(rawValue: raw) else {
            throw BackupError.malformed(reason: "pet.species")
        }
        return value
    }

    func requireSex(_ raw: String) throws -> PetSex {
        guard let value = PetSex(rawValue: raw) else {
            throw BackupError.malformed(reason: "pet.sex")
        }
        return value
    }

    func requireRecordType(_ raw: String) throws -> RecordType {
        guard let value = RecordType(rawValue: raw) else {
            throw BackupError.malformed(reason: "record.type")
        }
        return value
    }

    func requireReminderKind(_ raw: String) throws -> ReminderKind {
        guard let value = ReminderKind(rawValue: raw) else {
            throw BackupError.malformed(reason: "reminder.kind")
        }
        return value
    }

    func requireRepeatRule(_ raw: String) throws -> RepeatRule {
        guard let value = RepeatRule(rawValue: raw) else {
            throw BackupError.malformed(reason: "reminder.repeatRule")
        }
        return value
    }

    func requireAttachmentKind(_ raw: String) throws -> AttachmentKind {
        guard let value = AttachmentKind(rawValue: raw) else {
            throw BackupError.malformed(reason: "attachment.kind")
        }
        return value
    }

    /// base64 解码；非法内容直接报结构损坏，不做静默丢弃
    static func decodeBase64(_ raw: String?, field: String) throws -> Data? {
        guard let raw else { return nil }
        guard let data = Data(base64Encoded: raw) else {
            throw BackupError.malformed(reason: field)
        }
        return data
    }

    /// 解析 "1.0" 形式的版本号为可比较元组
    static func parseVersion(_ raw: String) throws -> (Int, Int) {
        let parts = raw.split(separator: ".")
        guard parts.count == 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            throw BackupError.malformed(reason: "version")
        }
        return (major, minor)
    }
}
