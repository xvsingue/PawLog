//
//  SyncTransport.swift
//  PawLog
//
//  同步抽象：与具体云端无关。当前只提供本地目录实现（LocalDirectoryTransport），
//  接入 CloudKit 时替换实现即可，SyncEngine 与冲突策略不变。
//

import Foundation

/// 可同步实体
enum SyncEntityKind: String, CaseIterable {
    case pet = "Pet"
    case record = "Record"
    case weightEntry = "WeightEntry"
    case reminder = "Reminder"
    case attachment = "Attachment"
}

/// 一次待推送的本地变更
struct LocalChange: Codable, Equatable {
    var entityName: String
    var entityID: UUID
    var operation: String
    var changeTag: String
    var deviceID: String
    var updatedAt: Date
    var deletedAt: Date?
    var payloadJSON: String

    /// 推送去重键：同一实体 + 同一变更标记视为同一条
    var dedupeKey: String { "\(entityName)|\(entityID.uuidString)|\(changeTag)" }

    var entityKind: SyncEntityKind? { SyncEntityKind(rawValue: entityName) }
}

/// 远端返回的一条变更
struct RemoteChange: Codable, Equatable {
    var entityName: String
    var entityID: UUID
    var operation: String
    var changeTag: String
    var deviceID: String
    var updatedAt: Date
    var deletedAt: Date?
    var payloadJSON: String

    var dedupeKey: String { "\(entityName)|\(entityID.uuidString)|\(changeTag)" }

    init(local: LocalChange) {
        entityName = local.entityName
        entityID = local.entityID
        operation = local.operation
        changeTag = local.changeTag
        deviceID = local.deviceID
        updatedAt = local.updatedAt
        deletedAt = local.deletedAt
        payloadJSON = local.payloadJSON
    }

    init(
        entityName: String,
        entityID: UUID,
        operation: String,
        changeTag: String,
        deviceID: String,
        updatedAt: Date,
        deletedAt: Date?,
        payloadJSON: String
    ) {
        self.entityName = entityName
        self.entityID = entityID
        self.operation = operation
        self.changeTag = changeTag
        self.deviceID = deviceID
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.payloadJSON = payloadJSON
    }
}

/// 同步传输层
protocol SyncTransport: AnyObject {
    /// 拉取 changeTag 之后的远端变更
    func pull(since changeTag: String) async throws -> [RemoteChange]
    /// 推送本地变更，返回发生冲突的 entityID
    func push(_ changes: [LocalChange]) async throws -> [UUID]
}
