//
//  SyncPayload.swift
//  PawLog
//
//  变更载荷编解码。直接复用备份 DTO，避免为同步再定义一套字段结构；
//  DTO 不含同步元数据，元数据随 RemoteChange 一起传输。
//

import Foundation
import SwiftData

enum SyncPayload {
    // MARK: - 编码

    static func json(
        for kind: SyncEntityKind,
        object: any SyncTracked,
        attachmentDirectory: URL
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data

        switch kind {
        case .pet:
            guard let pet = object as? Pet else { throw SyncError.entityMismatch }
            data = try encoder.encode(BackupService.petDTO(pet))
        case .record:
            guard let record = object as? Record else { throw SyncError.entityMismatch }
            data = try encoder.encode(BackupService.recordDTO(record))
        case .weightEntry:
            guard let entry = object as? WeightEntry else { throw SyncError.entityMismatch }
            data = try encoder.encode(BackupService.weightDTO(entry))
        case .reminder:
            guard let reminder = object as? Reminder else { throw SyncError.entityMismatch }
            data = try encoder.encode(BackupService.reminderDTO(reminder))
        case .attachment:
            guard let attachment = object as? Attachment else { throw SyncError.entityMismatch }
            data = try encoder.encode(
                BackupService.attachmentDTO(attachment, attachmentDirectory: attachmentDirectory)
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 解码

    static func decode<T: Decodable>(_ type: T.Type, _ remote: RemoteChange) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = remote.payloadJSON.data(using: .utf8) else {
            throw SyncError.malformedPayload
        }
        return try decoder.decode(type, from: data)
    }

    /// 把远端同步元数据写回本地对象
    static func applyMetadata(_ object: any SyncTracked, from remote: RemoteChange) {
        object.localUpdatedAt = remote.updatedAt
        object.deviceID = remote.deviceID
        object.changeTag = remote.changeTag
        object.deletedAt = remote.deletedAt
    }

    // MARK: - 查找

    static func pet(_ id: UUID, in context: ModelContext) throws -> Pet? {
        try context.fetch(FetchDescriptor<Pet>(predicate: #Predicate { $0.id == id })).first
    }

    static func record(_ id: UUID, in context: ModelContext) throws -> Record? {
        try context.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.id == id })).first
    }

    static func weightEntry(_ id: UUID, in context: ModelContext) throws -> WeightEntry? {
        try context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })).first
    }

    static func reminder(_ id: UUID, in context: ModelContext) throws -> Reminder? {
        try context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })).first
    }

    static func attachment(_ id: UUID, in context: ModelContext) throws -> Attachment? {
        try context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })).first
    }
}

/// 同步错误
enum SyncError: LocalizedError {
    case entityMismatch
    case malformedPayload
    case unknownEntity(String)

    var errorDescription: String? {
        switch self {
        case .entityMismatch:
            return String(localized: "sync.error.entityMismatch")
        case .malformedPayload:
            return String(localized: "sync.error.malformedPayload")
        case let .unknownEntity(name):
            return String(localized: "sync.error.unknownEntity \(name)")
        }
    }
}
