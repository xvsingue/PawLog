//
//  ConflictResolver.swift
//  PawLog
//
//  冲突解决策略。选择理由：
//  1. 删除优先：只要任一端存在墓碑，删除即胜出。否则「A 删除、B 修改」会因修改时间
//     更晚而把数据救回来，产生"删了又回来"的体验，且用户无法理解。
//  2. 非删除冲突取 localUpdatedAt 较新者（last-writer-wins）。宠物健康记录是
//     低并发场景，LWW 足够，且不需要向量时钟等额外状态。
//  3. 时间完全相同时按 deviceID 字典序较大者胜。必须有一个确定性决胜规则，
//     否则两台设备的合并结果可能不一致、无法复现。
//  4. 落败版本不丢弃，写入 ConflictLog，便于事后排查。
//

import Foundation

/// 冲突裁决结果
enum ConflictWinner {
    case local
    case remote
}

/// 冲突裁决器
enum ConflictResolver {
    /// 比较两条变更，判断谁胜出
    static func resolve(local: LocalChange, remote: RemoteChange) -> ConflictWinner {
        // 1. 删除优先
        switch (local.deletedAt, remote.deletedAt) {
        case (.some, .none):
            return .local
        case (.none, .some):
            return .remote
        case (.some, .some):
            return newer(local: local.updatedAt, localDevice: local.deviceID,
                          remote: remote.updatedAt, remoteDevice: remote.deviceID)
        case (.none, .none):
            // 2. 时间较新者胜；3. 同时间按 deviceID 字典序
            return newer(local: local.updatedAt, localDevice: local.deviceID,
                         remote: remote.updatedAt, remoteDevice: remote.deviceID)
        }
    }

    /// 远端内部比较：同实体两条远端变更谁胜出
    static func resolve(local incoming: RemoteChange, existing: RemoteChange) -> ConflictWinner {
        let local = LocalChange(
            entityName: incoming.entityName,
            entityID: incoming.entityID,
            operation: incoming.operation,
            changeTag: incoming.changeTag,
            deviceID: incoming.deviceID,
            updatedAt: incoming.updatedAt,
            deletedAt: incoming.deletedAt,
            payloadJSON: incoming.payloadJSON
        )
        return resolve(local: local, remote: existing) == .local ? .local : .remote
    }

    private static func newer(
        local: Date,
        localDevice: String,
        remote: Date,
        remoteDevice: String
    ) -> ConflictWinner {
        if local != remote {
            return local > remote ? .local : .remote
        }
        // 字典序较大者胜，保证两台设备得到同一结论
        return localDevice >= remoteDevice ? .local : .remote
    }
}
