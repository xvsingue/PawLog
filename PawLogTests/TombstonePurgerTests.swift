//
//  TombstonePurgerTests.swift
//  PawLogTests
//
//  墓碑清理：未同步不清理；已同步且超期清理且计数正确；清理后备份只剩活跃数据。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class TombstonePurgerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var petService: PetService!
    private var recordService: RecordService!
    private var purger: TombstonePurger!

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        // 实体与墓碑都发生在 40 天前，保证早于默认保留期
        let oldClock = FixedClock(now.addingTimeInterval(-40 * 86_400))
        petService = PetService(context: context, deviceID: "device-test", clock: oldClock)
        recordService = RecordService(context: context, deviceID: "device-test", clock: oldClock)
        purger = TombstonePurger(context: context, clock: FixedClock(now))
    }

    override func tearDownWithError() throws {
        purger = nil
        recordService = nil
        petService = nil
        context = nil
        container = nil
    }

    // MARK: - 工具

    private func makePetWithDeletedRecord() throws -> (Pet, Record) {
        let pet = Pet(name: "咪咪", species: .cat)
        try petService.createPet(pet)
        let record = try recordService.create(
            pet: pet,
            type: .daily,
            occurredAt: now.addingTimeInterval(-40 * 86_400),
            title: "旧日常",
            note: nil,
            payloadJSON: "",
            now: now.addingTimeInterval(-40 * 86_400)
        )
        try recordService.delete(record)
        return (pet, record)
    }

    private func markAllLogsSynced() throws {
        for log in try context.fetch(FetchDescriptor<ChangeLog>()) {
            log.synced = true
        }
        try context.save()
    }

    // MARK: - 未同步保留

    func testUnsyncedTombstoneIsKept() throws {
        let (_, record) = try makePetWithDeletedRecord()

        let result = try purger.purge()

        XCTAssertEqual(result, .zero)
        XCTAssertNotNil(record.deletedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Record>()).count, 1)
    }

    // MARK: - 已同步且超期清理

    func testSyncedExpiredTombstoneIsPurged() throws {
        let (_, _) = try makePetWithDeletedRecord()
        try markAllLogsSynced()

        let result = try purger.purge()

        XCTAssertEqual(result.records, 1)
        XCTAssertEqual(result.total, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Record>()).isEmpty)
        // 宠物本身没有删除，不应被清理
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pet>()).count, 1)
    }

    /// 宠物墓碑必须等子实体都可清理后再整棵子树一起清理
    func testSyncedExpiredPetTombstonePurgesWholeSubtree() throws {
        let pet = Pet(name: "要删的猫", species: .cat)
        try petService.createPet(pet)
        try recordService.create(
            pet: pet,
            type: .weight,
            occurredAt: now.addingTimeInterval(-40 * 86_400),
            title: "4.2 kg",
            note: nil,
            payloadJSON: PayloadCoding.encode(WeightPayload(weightKg: 4.2)),
            weight: WeightInput(kg: 4.2, bcs: nil),
            now: now.addingTimeInterval(-40 * 86_400)
        )
        context.insert(Reminder(pet: pet, kind: .custom, dueAt: now))
        try context.save()

        try petService.deletePet(pet)
        try markAllLogsSynced()

        let result = try purger.purge()

        XCTAssertEqual(result.pets, 1)
        XCTAssertEqual(result.records, 1)
        XCTAssertEqual(result.weightEntries, 1)
        XCTAssertEqual(result.reminders, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Pet>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Record>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WeightEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Reminder>()).isEmpty)
    }

    // MARK: - 清理后备份

    func testBackupAfterPurgeOnlyContainsActiveData() throws {
        let pet = Pet(name: "咪咪", species: .cat)
        try petService.createPet(pet)
        let kept = try recordService.create(
            pet: pet,
            type: .daily,
            occurredAt: now,
            title: "保留",
            note: nil,
            payloadJSON: "",
            now: now
        )
        let removed = try recordService.create(
            pet: pet,
            type: .daily,
            occurredAt: now.addingTimeInterval(-40 * 86_400),
            title: "删掉",
            note: nil,
            payloadJSON: "",
            now: now.addingTimeInterval(-40 * 86_400)
        )
        try recordService.delete(removed)
        try markAllLogsSynced()
        _ = try purger.purge()

        let backup = BackupService(context: context, clock: FixedClock(now))
        let envelope = try backup.makeBackup()
        XCTAssertEqual(envelope.records.map(\.id), [kept.id])
        XCTAssertEqual(envelope.counts.records, 1)
        let existing = try backup.existingCounts()
        XCTAssertEqual(existing.records, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Record>()).count, 1)
    }
}
