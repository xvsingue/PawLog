//
//  TombstoneVisibilityTests.swift
//  PawLogTests
//
//  墓碑隔离：已删除的 Record / Pet 不得出现在时间线、搜索、摘要、趋势、
//  宠物切换条、宠物列表、摘要选择列表与备份计数中。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class TombstoneVisibilityTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var petService: PetService!
    private var recordService: RecordService!
    private var pet: Pet!

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        petService = PetService(context: context, deviceID: "device-test", clock: FixedClock(now))
        recordService = RecordService(context: context, deviceID: "device-test", clock: FixedClock(now))
        pet = Pet(name: "咪咪", species: .cat)
        try petService.createPet(pet)
    }

    override func tearDownWithError() throws {
        pet = nil
        recordService = nil
        petService = nil
        context = nil
        container = nil
    }

    // MARK: - 工具

    @discardableResult
    private func addRecord(_ type: RecordType = .daily, title: String) throws -> Record {
        try recordService.create(
            pet: pet,
            type: type,
            occurredAt: now,
            title: title,
            note: nil,
            payloadJSON: "",
            now: now
        )
    }

    @discardableResult
    private func addWeightRecord(kg: Double, daysAgo: Int) throws -> Record {
        let date = now.addingTimeInterval(Double(-daysAgo) * 86_400)
        return try recordService.create(
            pet: pet,
            type: .weight,
            occurredAt: date,
            title: "\(kg) kg",
            note: nil,
            payloadJSON: PayloadCoding.encode(WeightPayload(weightKg: kg)),
            weight: WeightInput(kg: kg, bcs: nil),
            now: now
        )
    }

    // MARK: - 墓碑记录

    func testTimelineAndSearchExcludeTombstonedRecord() throws {
        let kept = try addRecord(title: "留下")
        let removed = try addRecord(title: "删掉")
        try recordService.delete(removed)

        // 时间线 @Query 使用的同一谓词
        let timeline = try context.fetch(FetchDescriptor<Record>(predicate: ActivePredicates.records))
        XCTAssertEqual(timeline.map(\.id), [kept.id])
        // 搜索只在活跃记录上进行
        XCTAssertTrue(TimelineSearch.filter(timeline, query: "删掉").isEmpty)
        XCTAssertEqual(TimelineSearch.filter(timeline, query: "留下").map(\.id), [kept.id])
        // 关系数组同样不包含墓碑
        XCTAssertEqual(pet.records.active.map(\.id), [kept.id])
    }

    func testSummaryAndTrendExcludeTombstonedRecord() throws {
        let early = try addWeightRecord(kg: 4.0, daysAgo: 10)
        let late = try addWeightRecord(kg: 5.0, daysAgo: 0)

        // 再插一条墓碑体重，模拟来自远端的删除
        let tombstone = WeightEntry(pet: pet, weightKg: 9.9, date: now)
        context.insert(tombstone)
        tombstone.deletedAt = now
        try context.save()

        try recordService.delete(late)

        let snapshot = SummarySnapshotBuilder.make(pet: pet, now: now)
        XCTAssertEqual(snapshot.records.map(\.id), [early.id])
        // 只剩一条 4.0 的体重，变化为 0，墓碑里的 5.0 / 9.9 不得参与
        XCTAssertEqual(
            snapshot.weightChange?.startText,
            snapshot.weightChange?.endText,
            "墓碑体重不应参与体重变化计算"
        )

        let trend = WeightTrendService(calendar: .current, clock: FixedClock(now))
        XCTAssertEqual(trend.latestPoint(for: pet)?.weightKg, 4.0)
        XCTAssertEqual(trend.points(for: pet, days: 90).count, 1)
        XCTAssertNil(trend.recentChange(for: pet))
        XCTAssertNil(trend.alert(for: pet))
    }

    func testPetSwitcherAndPickerExcludeTombstonedPet() throws {
        let other = Pet(name: "另一只", species: .dog)
        try petService.createPet(other)
        try addRecord(title: "旧记录")

        try petService.deletePet(pet)

        // 切换条与摘要选择列表都来自 fetchPets()
        let activePets = try petService.fetchPets()
        XCTAssertEqual(activePets.map(\.id), [other.id])
        XCTAssertFalse(activePets.contains { $0.id == pet.id })
        // @Query 使用同一谓词
        let queryPets = try context.fetch(FetchDescriptor<Pet>(predicate: ActivePredicates.pets))
        XCTAssertEqual(queryPets.map(\.id), [other.id])
        // 已删除宠物的子记录不参与统计
        XCTAssertEqual(petService.countRecords(for: pet), 0)
        let activeRecords = try context.fetch(FetchDescriptor<Record>(predicate: ActivePredicates.records))
        XCTAssertTrue(activeRecords.isEmpty)
    }

    func testBackupExcludesTombstonedData() throws {
        let kept = try addRecord(title: "留下")
        let removed = try addRecord(title: "删掉")

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("visibility-\(UUID().uuidString).pdf")
        try Data([0x01, 0x02]).write(to: fileURL)
        let attachment = Attachment(record: removed, kind: .pdf, localPath: fileURL.path)
        context.insert(attachment)
        try context.save()

        try recordService.delete(removed)

        let backup = BackupService(context: context, clock: FixedClock(now))
        let existing = try backup.existingCounts()
        XCTAssertEqual(existing.records, 1)
        let envelope = try backup.makeBackup()
        XCTAssertEqual(envelope.records.map(\.id), [kept.id])
        XCTAssertTrue(envelope.attachments.isEmpty, "墓碑记录下的附件不应导出")
        XCTAssertEqual(envelope.counts.records, 1)
        XCTAssertEqual(envelope.counts.attachments, 0)
    }
}
