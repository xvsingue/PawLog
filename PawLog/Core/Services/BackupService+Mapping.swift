//
//  BackupService+Mapping.swift
//  PawLog
//
//  SwiftData 模型与备份 DTO 之间的双向映射。
//

import Foundation
import SwiftData

extension BackupService {
    // MARK: - 模型 → DTO

    static func petDTO(_ pet: Pet) -> BackupPet {
        BackupPet(
            id: pet.id,
            name: pet.name,
            species: pet.species.rawValue,
            breed: pet.breed,
            birthday: pet.birthday,
            birthEstimated: pet.birthEstimated,
            sex: pet.sex.rawValue,
            neutered: pet.neutered,
            idealWeightKg: pet.idealWeightKg,
            allergies: pet.allergies,
            foodBrand: pet.foodBrand,
            chipID: pet.chipID,
            avatarDataBase64: pet.avatarData?.base64EncodedString(),
            archived: pet.archived,
            sortIndex: pet.sortIndex,
            createdAt: pet.createdAt
        )
    }

    static func recordDTO(_ record: Record) -> BackupRecord {
        BackupRecord(
            id: record.id,
            petID: record.pet?.id,
            type: record.type.rawValue,
            occurredAt: record.occurredAt,
            title: record.title,
            note: record.note,
            payloadJSON: record.payloadJSON,
            createdBy: record.createdBy,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    static func weightDTO(_ entry: WeightEntry) -> BackupWeightEntry {
        BackupWeightEntry(
            id: entry.id,
            petID: entry.pet?.id,
            weightKg: entry.weightKg,
            bcs: entry.bcs,
            date: entry.date,
            recordID: entry.recordID
        )
    }

    static func reminderDTO(_ reminder: Reminder) -> BackupReminder {
        BackupReminder(
            id: reminder.id,
            petID: reminder.pet?.id,
            kind: reminder.kind.rawValue,
            sourceRecordID: reminder.sourceRecordID,
            dueAt: reminder.dueAt,
            repeatRule: reminder.repeatRule.rawValue,
            enabled: reminder.enabled,
            lastDoneAt: reminder.lastDoneAt
        )
    }

    static func attachmentDTO(_ attachment: Attachment, fileManager: FileManager) -> BackupAttachment {
        let data = fileManager.contents(atPath: attachment.localPath)
        return BackupAttachment(
            id: attachment.id,
            recordID: attachment.record?.id,
            kind: attachment.kind.rawValue,
            localPath: attachment.localPath,
            fileDataBase64: data?.base64EncodedString(),
            thumbnailDataBase64: attachment.thumbnailData?.base64EncodedString(),
            createdAt: attachment.createdAt
        )
    }

    // MARK: - DTO → 模型

    /// 在已清空的上下文里按依赖顺序写入宠物 → 记录 → 体重 / 提醒 / 附件
    func insert(_ envelope: BackupEnvelope) throws {
        var petsByID: [UUID: Pet] = [:]
        for dto in envelope.pets {
            let pet = Pet(
                id: dto.id,
                name: dto.name,
                species: try requireSpecies(dto.species),
                breed: dto.breed,
                birthday: dto.birthday,
                birthEstimated: dto.birthEstimated,
                sex: try requireSex(dto.sex),
                neutered: dto.neutered,
                idealWeightKg: dto.idealWeightKg,
                allergies: dto.allergies,
                foodBrand: dto.foodBrand,
                chipID: dto.chipID,
                avatarData: try Self.decodeBase64(dto.avatarDataBase64, field: "pet.avatarData"),
                archived: dto.archived,
                sortIndex: dto.sortIndex,
                createdAt: dto.createdAt
            )
            context.insert(pet)
            petsByID[dto.id] = pet
        }

        var recordsByID: [UUID: Record] = [:]
        for dto in envelope.records {
            let record = Record(
                id: dto.id,
                pet: dto.petID.flatMap { petsByID[$0] },
                type: try requireRecordType(dto.type),
                occurredAt: dto.occurredAt,
                title: dto.title,
                note: dto.note,
                payloadJSON: dto.payloadJSON,
                createdBy: dto.createdBy,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
            context.insert(record)
            recordsByID[dto.id] = record
        }

        for dto in envelope.weightEntries {
            context.insert(
                WeightEntry(
                    id: dto.id,
                    pet: dto.petID.flatMap { petsByID[$0] },
                    weightKg: dto.weightKg,
                    bcs: dto.bcs,
                    date: dto.date,
                    recordID: dto.recordID
                )
            )
        }

        for dto in envelope.reminders {
            context.insert(
                Reminder(
                    id: dto.id,
                    pet: dto.petID.flatMap { petsByID[$0] },
                    kind: try requireReminderKind(dto.kind),
                    sourceRecordID: dto.sourceRecordID,
                    dueAt: dto.dueAt,
                    repeatRule: try requireRepeatRule(dto.repeatRule),
                    enabled: dto.enabled,
                    lastDoneAt: dto.lastDoneAt
                )
            )
        }

        for dto in envelope.attachments {
            let fileData = try Self.decodeBase64(dto.fileDataBase64, field: "attachment.file")
            context.insert(
                Attachment(
                    id: dto.id,
                    record: dto.recordID.flatMap { recordsByID[$0] },
                    kind: try requireAttachmentKind(dto.kind),
                    localPath: try restoreFile(
                        attachmentID: dto.id,
                        originalPath: dto.localPath,
                        data: fileData
                    ),
                    thumbnailData: try Self.decodeBase64(dto.thumbnailDataBase64, field: "attachment.thumbnail"),
                    createdAt: dto.createdAt
                )
            )
        }
    }

    /// 把附件字节写回本地目录，返回新的本地路径
    private func restoreFile(attachmentID: UUID, originalPath: String, data: Data?) throws -> String {
        guard let data else { return originalPath }
        do {
            try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            let ext = (originalPath as NSString).pathExtension
            let name = ext.isEmpty ? attachmentID.uuidString : "\(attachmentID.uuidString).\(ext)"
            let url = attachmentDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            throw BackupError.malformed(reason: String(localized: "settings.backup.error.attachmentWrite"))
        }
    }
}
