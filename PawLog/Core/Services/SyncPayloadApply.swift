//
//  SyncPayloadApply.swift
//  PawLog
//
//  把远端变更写入本地：存在则更新，不存在则新建。
//  已删除（墓碑）的远端变更只更新元数据，不重建业务字段。
//

import Foundation
import SwiftData

extension SyncPayload {
    /// 应用一条远端变更
    static func apply(
        _ remote: RemoteChange,
        in context: ModelContext,
        attachmentDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        guard let kind = SyncEntityKind(rawValue: remote.entityName) else {
            throw SyncError.unknownEntity(remote.entityName)
        }

        switch kind {
        case .pet:
            try applyPet(remote, in: context)
        case .record:
            try applyRecord(remote, in: context)
        case .weightEntry:
            try applyWeight(remote, in: context)
        case .reminder:
            try applyReminder(remote, in: context)
        case .attachment:
            try applyAttachment(remote, in: context, directory: attachmentDirectory, fileManager: fileManager)
        }
    }

    // MARK: - Pet

    private static func applyPet(_ remote: RemoteChange, in context: ModelContext) throws {
        let dto = try decode(BackupPet.self, remote)
        let pet: Pet
        if let existing = try Self.pet(dto.id, in: context) {
            pet = existing
        } else {
            guard let species = PetSpecies(rawValue: dto.species) else {
                throw SyncError.malformedPayload
            }
            pet = Pet(id: dto.id, name: dto.name, species: species)
            context.insert(pet)
        }
        pet.name = dto.name
        pet.species = PetSpecies(rawValue: dto.species) ?? pet.species
        pet.breed = dto.breed
        pet.birthday = dto.birthday
        pet.birthEstimated = dto.birthEstimated
        pet.sex = PetSex(rawValue: dto.sex) ?? pet.sex
        pet.neutered = dto.neutered
        pet.idealWeightKg = dto.idealWeightKg
        pet.allergies = dto.allergies
        pet.foodBrand = dto.foodBrand
        pet.chipID = dto.chipID
        pet.avatarData = try BackupService.decodeBase64(dto.avatarDataBase64, field: "pet.avatarData")
        pet.archived = dto.archived
        pet.sortIndex = dto.sortIndex
        pet.createdAt = dto.createdAt
        applyMetadata(pet, from: remote)
    }

    // MARK: - Record

    private static func applyRecord(_ remote: RemoteChange, in context: ModelContext) throws {
        let dto = try decode(BackupRecord.self, remote)
        let record: Record
        if let existing = try Self.record(dto.id, in: context) {
            record = existing
        } else {
            guard let type = RecordType(rawValue: dto.type) else {
                throw SyncError.malformedPayload
            }
            record = Record(id: dto.id, type: type, occurredAt: dto.occurredAt, title: dto.title)
            context.insert(record)
        }
        record.pet = try dto.petID.flatMap { try Self.pet($0, in: context) }
        record.type = RecordType(rawValue: dto.type) ?? record.type
        record.occurredAt = dto.occurredAt
        record.title = dto.title
        record.note = dto.note
        record.payloadJSON = dto.payloadJSON
        record.createdBy = dto.createdBy
        record.createdAt = dto.createdAt
        record.updatedAt = dto.updatedAt
        applyMetadata(record, from: remote)
    }

    // MARK: - WeightEntry

    private static func applyWeight(_ remote: RemoteChange, in context: ModelContext) throws {
        let dto = try decode(BackupWeightEntry.self, remote)
        let entry: WeightEntry
        if let existing = try weightEntry(dto.id, in: context) {
            entry = existing
        } else {
            entry = WeightEntry(id: dto.id, weightKg: dto.weightKg, date: dto.date)
            context.insert(entry)
        }
        entry.pet = try dto.petID.flatMap { try pet($0, in: context) }
        entry.weightKg = dto.weightKg
        entry.bcs = dto.bcs
        entry.date = dto.date
        entry.recordID = dto.recordID
        applyMetadata(entry, from: remote)
    }

    // MARK: - Reminder

    private static func applyReminder(_ remote: RemoteChange, in context: ModelContext) throws {
        let dto = try decode(BackupReminder.self, remote)
        let reminder: Reminder
        if let existing = try Self.reminder(dto.id, in: context) {
            reminder = existing
        } else {
            guard let kind = ReminderKind(rawValue: dto.kind) else {
                throw SyncError.malformedPayload
            }
            reminder = Reminder(id: dto.id, kind: kind, dueAt: dto.dueAt)
            context.insert(reminder)
        }
        reminder.pet = try dto.petID.flatMap { try Self.pet($0, in: context) }
        reminder.kind = ReminderKind(rawValue: dto.kind) ?? reminder.kind
        reminder.sourceRecordID = dto.sourceRecordID
        reminder.dueAt = dto.dueAt
        reminder.repeatRule = RepeatRule(rawValue: dto.repeatRule) ?? reminder.repeatRule
        reminder.enabled = dto.enabled
        reminder.lastDoneAt = dto.lastDoneAt
        applyMetadata(reminder, from: remote)
    }

    // MARK: - Attachment

    private static func applyAttachment(
        _ remote: RemoteChange,
        in context: ModelContext,
        directory: URL,
        fileManager: FileManager
    ) throws {
        let dto = try decode(BackupAttachment.self, remote)
        let attachment: Attachment
        if let existing = try Self.attachment(dto.id, in: context) {
            attachment = existing
        } else {
            guard let kind = AttachmentKind(rawValue: dto.kind) else {
                throw SyncError.malformedPayload
            }
            attachment = Attachment(id: dto.id, kind: kind, localPath: dto.localPath)
            context.insert(attachment)
        }
        attachment.record = try dto.recordID.flatMap { try Self.record($0, in: context) }
        attachment.kind = AttachmentKind(rawValue: dto.kind) ?? attachment.kind
        attachment.createdAt = dto.createdAt
        attachment.thumbnailData = try BackupService.decodeBase64(
            dto.thumbnailDataBase64, field: "attachment.thumbnail"
        )
        attachment.localPath = try restoreFile(
            attachmentID: dto.id,
            recordID: dto.recordID,
            storedPath: dto.localPath,
            data: try BackupService.decodeBase64(dto.fileDataBase64, field: "attachment.file"),
            directory: directory,
            fileManager: fileManager
        )
        applyMetadata(attachment, from: remote)
    }

    /// 写入附件文件并返回相对路径（attachments/...）
    private static func restoreFile(
        attachmentID: UUID,
        recordID: UUID?,
        storedPath: String,
        data: Data?,
        directory: URL,
        fileManager: FileManager
    ) throws -> String {
        let relative = BackupService.storedRelativePath(
            storedPath: storedPath,
            attachmentID: attachmentID,
            recordID: recordID
        )
        let url = AttachmentStore(directory: directory).url(forStoredPath: relative)
        guard let data else { return relative }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return relative
    }
}
