//
//  BackupModels.swift
//  PawLog
//
//  备份文件的传输结构。与 SwiftData 模型解耦，用 petID / recordID 表达关系，
//  便于后续 schema 演进与独立单元测试。
//

import Foundation

/// 备份服务错误
enum BackupError: LocalizedError, Equatable {
    /// 文件版本高于当前支持
    case versionTooNew(file: String, supported: String)
    /// 文件版本低于当前支持
    case versionTooOld(file: String, supported: String)
    /// schema 版本不一致
    case schemaVersionMismatch(file: Int, supported: Int)
    /// 结构损坏、字段缺失、base64 非法、关系悬空等
    case malformed(reason: String)
    /// 本地已有数据且未确认覆盖
    case overwriteNotConfirmed(existingRecords: Int)

    var errorDescription: String? {
        switch self {
        case let .versionTooNew(file, supported):
            return String(localized: "settings.backup.error.versionNew \(file) \(supported)")
        case let .versionTooOld(file, supported):
            return String(localized: "settings.backup.error.versionOld \(file) \(supported)")
        case let .schemaVersionMismatch(file, supported):
            return String(localized: "settings.backup.error.schema \(file) \(supported)")
        case let .malformed(reason):
            return String(localized: "settings.backup.error.malformed \(reason)")
        case let .overwriteNotConfirmed(count):
            return String(localized: "settings.backup.error.needConfirm \(count)")
        }
    }
}

/// 各模型条数，用于导入前后的完整性校验
struct BackupCounts: Codable, Equatable {
    var pets: Int
    var records: Int
    var weightEntries: Int
    var reminders: Int
    var attachments: Int

    var total: Int {
        pets + records + weightEntries + reminders + attachments
    }

    static let zero = BackupCounts(
        pets: 0, records: 0, weightEntries: 0, reminders: 0, attachments: 0
    )
}

/// 宠物
struct BackupPet: Codable {
    var id: UUID
    var name: String
    var species: String
    var breed: String?
    var birthday: Date?
    var birthEstimated: Bool
    var sex: String
    var neutered: Bool?
    var idealWeightKg: Double?
    var allergies: String?
    var foodBrand: String?
    var chipID: String?
    /// 头像原始字节，base64 内嵌
    var avatarDataBase64: String?
    var archived: Bool
    var sortIndex: Int
    var createdAt: Date
}

/// 记录
struct BackupRecord: Codable {
    var id: UUID
    var petID: UUID?
    var type: String
    var occurredAt: Date
    var title: String
    var note: String?
    var payloadJSON: String
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date
}

/// 体重
struct BackupWeightEntry: Codable {
    var id: UUID
    var petID: UUID?
    var weightKg: Double
    var bcs: Int?
    var date: Date
    var recordID: UUID?
}

/// 提醒
struct BackupReminder: Codable {
    var id: UUID
    var petID: UUID?
    var kind: String
    var sourceRecordID: UUID?
    var dueAt: Date
    var repeatRule: String
    var enabled: Bool
    var lastDoneAt: Date?
}

/// 附件。二进制与缩略图均以 base64 内嵌。
struct BackupAttachment: Codable {
    var id: UUID
    var recordID: UUID?
    var kind: String
    var localPath: String
    /// 附件文件本体
    var fileDataBase64: String?
    /// 列表缩略图
    var thumbnailDataBase64: String?
    var createdAt: Date
}

/// 备份文件顶层结构
struct BackupEnvelope: Codable {
    var version: String
    var schemaVersion: Int
    var exportedAt: Date
    var counts: BackupCounts
    var pets: [BackupPet]
    var records: [BackupRecord]
    var weightEntries: [BackupWeightEntry]
    var reminders: [BackupReminder]
    var attachments: [BackupAttachment]
}
