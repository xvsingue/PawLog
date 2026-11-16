//
//  ChangeLogService.swift
//  PawLog
//
//  Service 层写操作的统一变更记录入口。任何 create / update / delete 都必须
//  经过 record(...)，否则该变更不会被同步。
//

import Foundation
import SwiftData

/// 设备标识：首次启动生成并持久化，用于冲突决胜
enum DeviceIdentity {
    static let storageKey = "pawlog.deviceID"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let value = defaults.string(forKey: storageKey), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: storageKey)
        return value
    }
}

@MainActor
final class ChangeLogService {
    private let context: ModelContext
    private let deviceID: String
    private let clock: Clock
    private let fileManager: FileManager

    init(
        context: ModelContext,
        deviceID: String = DeviceIdentity.current(),
        clock: Clock = SystemClock(),
        fileManager: FileManager = .default
    ) {
        self.context = context
        self.deviceID = deviceID
        self.clock = clock
        self.fileManager = fileManager
    }

    /// 写入同步元数据并记录一条变更日志。调用方负责 save。
    @discardableResult
    func record(
        _ object: any SyncTracked,
        kind: SyncEntityKind,
        operation: ChangeOperation,
        at now: Date? = nil
    ) throws -> ChangeLog {
        let timestamp = now ?? clock.now
        object.localUpdatedAt = timestamp
        object.deviceID = deviceID
        object.changeTag = UUID().uuidString

        let payload = try SyncPayload.json(for: kind, object: object, fileManager: fileManager)
        let log = ChangeLog(
            entityName: kind.rawValue,
            entityID: object.id,
            operation: operation,
            payloadJSON: payload,
            changeTag: object.changeTag,
            createdAt: timestamp
        )
        context.insert(log)
        return log
    }

    /// 未推送的变更日志，按时间升序
    func pendingLogs() throws -> [ChangeLog] {
        let descriptor = FetchDescriptor<ChangeLog>(
            predicate: #Predicate { !$0.synced },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// 标记已推送
    func markSynced(_ logs: [ChangeLog]) throws {
        for log in logs { log.synced = true }
        try context.save()
    }
}
