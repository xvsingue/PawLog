//
//  SyncEngine.swift
//  PawLog
//
//  同步内核：收集本地未同步的 ChangeLog → 合并为 LocalChange → 交给 transport →
//  处理冲突 → 标记已同步；随后拉取远端变更并应用。
//
//  设计取舍：同步只做"推 + 拉"两段，不做后台增量游标持久化。since 由调用方
//  传入（当前实现传空表示全量拉取），接入 CloudKit 时换成服务端 changeToken 即可。
//

import Foundation
import SwiftData

@MainActor
final class SyncEngine {
    private let context: ModelContext
    private let transport: any SyncTransport
    private let deviceID: String
    private let clock: Clock
    private let fileManager: FileManager
    private let attachmentDirectory: URL

    init(
        context: ModelContext,
        transport: any SyncTransport,
        deviceID: String,
        clock: Clock = SystemClock(),
        fileManager: FileManager = .default,
        attachmentDirectory: URL? = nil
    ) {
        self.context = context
        self.transport = transport
        self.deviceID = deviceID
        self.clock = clock
        self.fileManager = fileManager
        self.attachmentDirectory = attachmentDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("sync-attachments", isDirectory: true)
    }

    /// 推 + 拉。返回本次应用的远端变更数。
    @discardableResult
    func sync() async throws -> Int {
        _ = try await pushPending()
        return try await pullAndApply()
    }

    // MARK: - 推送

    /// 推送本地未同步变更，返回发生冲突的 entityID
    @discardableResult
    func pushPending() async throws -> [UUID] {
        let service = ChangeLogService(
            context: context,
            deviceID: deviceID,
            clock: clock,
            fileManager: fileManager
        )
        let logs = try service.pendingLogs()
        guard !logs.isEmpty else { return [] }

        // 同一实体多次变更只推送最后一条，避免重复往返；删除优先于其它操作
        var latest: [String: ChangeLog] = [:]
        for log in logs {
            let key = "\(log.entityName)|\(log.entityID.uuidString)"
            guard let existing = latest[key] else {
                latest[key] = log
                continue
            }
            if existing.operationKind == .delete { continue }
            if log.operationKind == .delete {
                latest[key] = log
            } else if log.createdAt >= existing.createdAt {
                latest[key] = log
            }
        }
        let changes: [LocalChange] = latest.values
            .sorted { lhs, rhs in
                let l = Self.entityOrder(lhs.entityName), r = Self.entityOrder(rhs.entityName)
                return l == r ? lhs.createdAt < rhs.createdAt : l < r
            }
            .compactMap { log in
                guard let kind = SyncEntityKind(rawValue: log.entityName) else { return nil }
                // 墓碑状态存在实体上而非 ChangeLog 里，推送时从实体现读；
                // 实体已被物理删除（如派生提醒）时退回日志时间，保证删除仍可传达。
                let live = try? currentChange(entityID: log.entityID, kind: kind)
                let deletedAt = live?.deletedAt
                    ?? (log.operationKind == .delete ? log.createdAt : nil)
                return LocalChange(
                    entityName: log.entityName,
                    entityID: log.entityID,
                    operation: log.operation,
                    changeTag: log.changeTag,
                    deviceID: deviceID,
                    updatedAt: log.createdAt,
                    deletedAt: deletedAt,
                    payloadJSON: log.payloadJSON
                )
            }

        let conflicts = try await transport.push(changes)

        for log in logs { log.synced = true }
        try context.save()

        if !conflicts.isEmpty {
            try await resolveConflicts(entityIDs: conflicts)
        }
        return conflicts
    }

    // MARK: - 冲突

    /// 对已推送但发生冲突的实体做裁决：胜出版本落到本地，落败版本写入 ConflictLog
    private func resolveConflicts(entityIDs: [UUID]) async throws {
        let remoteChanges = try await transport.pull(since: "")
        for entityID in entityIDs {
            guard let remote = remoteChanges.last(where: { $0.entityID == entityID }),
                  let kind = SyncEntityKind(rawValue: remote.entityName),
                  let local = try currentChange(entityID: entityID, kind: kind) else {
                continue
            }
            // 远端存的就是自己刚推上去的版本，不算冲突
            guard local.changeTag != remote.changeTag else { continue }
            switch ConflictResolver.resolve(local: local, remote: remote) {
            case .remote:
                try SyncPayload.apply(
                    remote,
                    in: context,
                    attachmentDirectory: attachmentDirectory,
                    fileManager: fileManager
                )
                insertConflictLog(kind: kind, winner: remote, loser: local)
            case .local:
                insertConflictLog(kind: kind, winner: local, loser: remote)
            }
        }
        try context.save()
    }

    private func insertConflictLog(kind: SyncEntityKind, winner: LocalChange, loser: RemoteChange) {
        context.insert(
            ConflictLog(
                entityName: kind.rawValue,
                entityID: loser.entityID,
                winnerDeviceID: winner.deviceID,
                loserDeviceID: loser.deviceID,
                loserJSON: loser.payloadJSON,
                createdAt: clock.now
            )
        )
    }

    private func insertConflictLog(kind: SyncEntityKind, winner: RemoteChange, loser: LocalChange) {
        context.insert(
            ConflictLog(
                entityName: kind.rawValue,
                entityID: loser.entityID,
                winnerDeviceID: winner.deviceID,
                loserDeviceID: loser.deviceID,
                loserJSON: loser.payloadJSON,
                createdAt: clock.now
            )
        )
    }

    // MARK: - 拉取

    /// 拉取远端变更并应用，返回应用条数
    @discardableResult
    func pullAndApply() async throws -> Int {
        let remoteChanges = try await transport.pull(since: "")
        var applied = 0

        // 按依赖顺序应用：宠物 → 记录 → 体重/提醒 → 附件，避免关系悬空
        let ordered = remoteChanges.sorted { lhs, rhs in
            let l = Self.entityOrder(lhs.entityName), r = Self.entityOrder(rhs.entityName)
            return l == r ? lhs.updatedAt < rhs.updatedAt : l < r
        }

        for remote in ordered {
            guard let kind = SyncEntityKind(rawValue: remote.entityName) else { continue }

            if let local = try currentChange(entityID: remote.entityID, kind: kind) {
                if local.changeTag == remote.changeTag { continue }
                switch ConflictResolver.resolve(local: local, remote: remote) {
                case .remote:
                    // 本地这版确实被本机写过（有对应 ChangeLog）才会丢失用户输入，
                    // 才需要保留落败快照；若本地只是远端应用下来的旧副本，则不算冲突。
                    if try hasLocalChangeLog(entityID: local.entityID, changeTag: local.changeTag) {
                        insertConflictLog(kind: kind, winner: remote, loser: local)
                    }
                    try SyncPayload.apply(
                        remote,
                        in: context,
                        attachmentDirectory: attachmentDirectory,
                        fileManager: fileManager
                    )
                    applied += 1
                case .local:
                    // 本地更新，留给下一次推送
                    continue
                }
            } else {
                // 本地没有该实体：墓碑没有恢复意义，直接跳过
                guard remote.deletedAt == nil else { continue }
                try SyncPayload.apply(
                    remote,
                    in: context,
                    attachmentDirectory: attachmentDirectory,
                    fileManager: fileManager
                )
                applied += 1
            }
        }

        if applied > 0 { try context.save() }
        return applied
    }

    // MARK: - 本地快照

    /// 推送与应用的依赖顺序：先宠物，再记录，再挂附属实体
    private static func entityOrder(_ name: String) -> Int {
        switch SyncEntityKind(rawValue: name) {
        case .pet: return 0
        case .record: return 1
        case .weightEntry, .reminder: return 2
        case .attachment: return 3
        case nil: return 4
        }
    }

    /// 该实体这一版是否是本机产生的变更（存在对应 ChangeLog）
    private func hasLocalChangeLog(entityID: UUID, changeTag: String) throws -> Bool {
        let descriptor = FetchDescriptor<ChangeLog>(
            predicate: #Predicate { $0.entityID == entityID && $0.changeTag == changeTag }
        )
        return try context.fetchCount(descriptor) > 0
    }

    private func currentChange(entityID: UUID, kind: SyncEntityKind) throws -> LocalChange? {
        let object: (any SyncTracked)?
        switch kind {
        case .pet:
            object = try SyncPayload.pet(entityID, in: context)
        case .record:
            object = try SyncPayload.record(entityID, in: context)
        case .weightEntry:
            object = try SyncPayload.weightEntry(entityID, in: context)
        case .reminder:
            object = try SyncPayload.reminder(entityID, in: context)
        case .attachment:
            object = try SyncPayload.attachment(entityID, in: context)
        }
        guard let object else { return nil }
        return try localChange(object, kind: kind)
    }

    private func localChange(_ object: any SyncTracked, kind: SyncEntityKind) throws -> LocalChange {
        LocalChange(
            entityName: kind.rawValue,
            entityID: object.id,
            operation: object.deletedAt == nil
                ? ChangeOperation.update.rawValue
                : ChangeOperation.delete.rawValue,
            changeTag: object.changeTag,
            deviceID: object.deviceID,
            updatedAt: object.localUpdatedAt,
            deletedAt: object.deletedAt,
            payloadJSON: try SyncPayload.json(for: kind, object: object, fileManager: fileManager)
        )
    }
}
