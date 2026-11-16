//
//  SyncTestSupport.swift
//  PawLogTests
//
//  同步测试夹具：一台"设备" = 一个独立 ModelContainer + 指向同一目录的
//  LocalDirectoryTransport。两台设备共享目录即可模拟同一份远端。
//

import Foundation
import SwiftData
@testable import PawLog

@MainActor
final class SyncDevice {
    let container: ModelContainer
    let context: ModelContext
    let deviceID: String
    let attachmentDirectory: URL
    let transport: LocalDirectoryTransport
    let engine: SyncEngine
    private let clock: FixedClock

    /// 每个测试独立的共享目录（模拟同一份远端存储）
    static func makeRootDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PawLogSyncTests-\(UUID().uuidString)", isDirectory: true)
    }

    init(deviceID: String, shareRootDirectory: URL, now: Date) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        self.deviceID = deviceID
        attachmentDirectory = shareRootDirectory
            .appendingPathComponent("attachments-\(deviceID)", isDirectory: true)
        clock = FixedClock(now)
        transport = LocalDirectoryTransport(directory: shareRootDirectory)
        engine = SyncEngine(
            context: context,
            transport: transport,
            deviceID: deviceID,
            clock: clock,
            attachmentDirectory: attachmentDirectory
        )
    }

    var petService: PetService {
        PetService(context: context, deviceID: deviceID, clock: clock)
    }

    var recordService: RecordService {
        RecordService(context: context, deviceID: deviceID, clock: clock)
    }

    var changeLogService: ChangeLogService {
        ChangeLogService(context: context, deviceID: deviceID, clock: clock)
    }

    func fetchRecords() throws -> [Record] {
        try context.fetch(FetchDescriptor<Record>())
    }
}
