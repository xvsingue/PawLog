//
//  SyncModels.swift
//  PawLog
//
//  变更日志与冲突日志。
//  ChangeLog 记录每一次本地写操作，供 SyncEngine 收集推送；
//  ConflictLog 保存冲突中落败的一版，用户不可见，仅供事后排查与备份保留。
//

import Foundation
import SwiftData

/// 写操作类型
enum ChangeOperation: String, Codable, CaseIterable {
    case create
    case update
    case delete
}

/// 本地变更日志
@Model
final class ChangeLog {
    var id: UUID
    /// 实体名，与 SwiftData 模型名一致：Pet / Record / WeightEntry / Reminder / Attachment
    var entityName: String
    var entityID: UUID
    /// 原始值见 ChangeOperation
    var operation: String
    /// 变更后的实体快照（JSON）
    var payloadJSON: String
    /// 该次变更的乐观并发标记
    var changeTag: String = ""
    var createdAt: Date
    /// 是否已成功推送
    var synced: Bool = false

    init(
        id: UUID = UUID(),
        entityName: String,
        entityID: UUID,
        operation: ChangeOperation,
        payloadJSON: String,
        changeTag: String,
        createdAt: Date,
        synced: Bool = false
    ) {
        self.id = id
        self.entityName = entityName
        self.entityID = entityID
        self.operation = operation.rawValue
        self.payloadJSON = payloadJSON
        self.changeTag = changeTag
        self.createdAt = createdAt
        self.synced = synced
    }

    var operationKind: ChangeOperation {
        ChangeOperation(rawValue: operation) ?? .update
    }
}

/// 冲突中落败的一版
@Model
final class ConflictLog {
    var id: UUID
    var entityName: String
    var entityID: UUID
    /// 胜出版本设备
    var winnerDeviceID: String
    /// 落败版本设备
    var loserDeviceID: String
    /// 落败版本的完整快照（JSON）
    var loserJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityName: String,
        entityID: UUID,
        winnerDeviceID: String,
        loserDeviceID: String,
        loserJSON: String,
        createdAt: Date
    ) {
        self.id = id
        self.entityName = entityName
        self.entityID = entityID
        self.winnerDeviceID = winnerDeviceID
        self.loserDeviceID = loserDeviceID
        self.loserJSON = loserJSON
        self.createdAt = createdAt
    }
}
