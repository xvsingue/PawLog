//
//  SyncEngineTests.swift
//  PawLogTests
//
//  M9a 同步内核：用两台独立 ModelContainer 共享同一目录模拟设备 A / B。
//  覆盖往返、LWW、确定性决胜、删除优先、幂等、附件二进制、冲突日志。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class SyncEngineTests: XCTestCase {
    private let baseTime = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - 工具

    private func makePair() throws -> (root: URL, a: SyncDevice, b: SyncDevice) {
        let root = SyncDevice.makeRootDirectory()
        let a = try SyncDevice(deviceID: "device-A", shareRootDirectory: root, now: baseTime)
        let b = try SyncDevice(deviceID: "device-B", shareRootDirectory: root, now: baseTime)
        return (root, a, b)
    }

    @discardableResult
    private func seedPetAndRecord(on device: SyncDevice) throws -> (Pet, Record) {
        let pet = Pet(name: "咪咪", species: .cat)
        try device.petService.createPet(pet)
        let record = try device.recordService.create(
            pet: pet,
            type: .daily,
            occurredAt: baseTime,
            title: "日常",
            note: "初始",
            payloadJSON: PayloadCoding.encode(DailyPayload(foodAmount: "50 g")),
            now: baseTime
        )
        return (pet, record)
    }

    private func record(withID id: UUID, on device: SyncDevice) throws -> Record? {
        try device.fetchRecords().first { $0.id == id }
    }

    // MARK: - 4.1 单设备往返

    func testSingleDevicePushPullRoundTrip() async throws {
        let (root, a, b) = try makePair()
        defer { try? FileManager.default.removeItem(at: root) }

        let (pet, _) = try seedPetAndRecord(on: a)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        let pets = try b.petService.fetchPets()
        XCTAssertEqual(pets.count, 1)
        XCTAssertEqual(pets.first?.id, pet.id)
        XCTAssertEqual(pets.first?.name, "咪咪")

        let records = try b.fetchRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.note, "初始")
        XCTAssertEqual(records.first?.pet?.id, pet.id)
    }

    // MARK: - 4.2 并发更新，较新者胜

    func testConcurrentUpdateNewestWins() async throws {
        let (root, a, b) = try makePair()
        defer { try? FileManager.default.removeItem(at: root) }

        let (_, seeded) = try seedPetAndRecord(on: a)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        let aRecord = try XCTUnwrap(try record(withID: seeded.id, on: a))
        let bRecord = try XCTUnwrap(try record(withID: seeded.id, on: b))

        try a.recordService.update(
            aRecord, occurredAt: baseTime, title: "日常", note: "A 版本",
            payloadJSON: aRecord.payloadJSON, now: baseTime.addingTimeInterval(50)
        )
        try b.recordService.update(
            bRecord, occurredAt: baseTime, title: "日常", note: "B 版本",
            payloadJSON: bRecord.payloadJSON, now: baseTime.addingTimeInterval(100)
        )

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()
        _ = try await a.engine.sync()

        XCTAssertEqual(aRecord.note, "B 版本", "较新的 B 版本应胜出")
        XCTAssertEqual(bRecord.note, "B 版本")
        XCTAssertEqual(aRecord.changeTag, bRecord.changeTag, "两边最终应一致")
    }

    // MARK: - 4.3 时间相同按 deviceID 决胜

    func testConcurrentUpdateDeterministicTieBreak() async throws {
        let tie = baseTime.addingTimeInterval(60)

        for _ in 0..<3 {
            let (root, a, b) = try makePair()
            defer { try? FileManager.default.removeItem(at: root) }

            let (_, seeded) = try seedPetAndRecord(on: a)
            _ = try await a.engine.sync()
            _ = try await b.engine.sync()

            let aRecord = try XCTUnwrap(try record(withID: seeded.id, on: a))
            let bRecord = try XCTUnwrap(try record(withID: seeded.id, on: b))

            try a.recordService.update(
                aRecord, occurredAt: baseTime, title: "日常", note: "A 版本",
                payloadJSON: aRecord.payloadJSON, now: tie
            )
            try b.recordService.update(
                bRecord, occurredAt: baseTime, title: "日常", note: "B 版本",
                payloadJSON: bRecord.payloadJSON, now: tie
            )

            _ = try await a.engine.sync()
            _ = try await b.engine.sync()
            _ = try await a.engine.sync()

            // device-B 字典序大于 device-A，恒定由 B 胜出
            XCTAssertEqual(aRecord.note, "B 版本")
            XCTAssertEqual(bRecord.note, "B 版本")
        }
    }

    // MARK: - 4.4 删除优先于修改

    func testTombstoneWinsOverUpdate() async throws {
        let (root, a, b) = try makePair()
        defer { try? FileManager.default.removeItem(at: root) }

        let (_, seeded) = try seedPetAndRecord(on: a)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        let aRecord = try XCTUnwrap(try record(withID: seeded.id, on: a))
        let bRecord = try XCTUnwrap(try record(withID: seeded.id, on: b))

        // B 先修改但未推送，A 随后删除
        try b.recordService.update(
            bRecord, occurredAt: baseTime, title: "日常", note: "B 改过了",
            payloadJSON: bRecord.payloadJSON, now: baseTime.addingTimeInterval(100)
        )
        try a.recordService.delete(aRecord)

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        XCTAssertNotNil(aRecord.deletedAt)
        XCTAssertNotNil(bRecord.deletedAt, "删除应胜出，B 的修改不能把记录救回来")
        XCTAssertEqual(try a.fetchRecords().filter { $0.deletedAt == nil }.count, 0)
        XCTAssertEqual(try b.fetchRecords().filter { $0.deletedAt == nil }.count, 0)
    }

    // MARK: - 4.5 重复推送幂等

    func testRepeatedPushIsIdempotent() async throws {
        let (root, a, _) = try makePair()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try seedPetAndRecord(on: a)
        _ = try await a.engine.pushPending()
        let afterFirst = try a.transport.allChanges()
        XCTAssertEqual(afterFirst.count, 2, "宠物与记录各一条")

        // 同一批变更再推一次，条数不翻倍
        _ = try await a.engine.pushPending()
        XCTAssertEqual(try a.transport.allChanges().count, afterFirst.count)

        // 直接把同一条变更重复交给 transport，也必须被去重
        let remote = try XCTUnwrap(afterFirst.first)
        let duplicate = LocalChange(
            entityName: remote.entityName,
            entityID: remote.entityID,
            operation: remote.operation,
            changeTag: remote.changeTag,
            deviceID: remote.deviceID,
            updatedAt: remote.updatedAt,
            deletedAt: remote.deletedAt,
            payloadJSON: remote.payloadJSON
        )
        _ = try await a.transport.push([duplicate])
        _ = try await a.transport.push([duplicate])
        XCTAssertEqual(try a.transport.allChanges().count, afterFirst.count)
    }

    // MARK: - 4.6 附件二进制往返

    func testAttachmentBinarySync() async throws {
        let (root, a, b) = try makePair()
        defer { try? FileManager.default.removeItem(at: root) }

        let (_, record) = try seedPetAndRecord(on: a)

        let bytes = Data((0..<512).map { UInt8($0 % 251) })
        let relative = "attachments/\(record.id.uuidString)/xray.pdf"
        let fileURL = AttachmentStore(directory: a.attachmentDirectory)
            .url(forStoredPath: relative)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try bytes.write(to: fileURL)
        let thumbnail = Data([0x01, 0x02, 0x03, 0x04])

        let attachment = Attachment(
            record: record, kind: .pdf, localPath: relative, thumbnailData: thumbnail
        )
        a.context.insert(attachment)
        try a.changeLogService.record(attachment, kind: .attachment, operation: .create)
        try a.context.save()

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        let pulled = try XCTUnwrap(try b.context.fetch(FetchDescriptor<Attachment>()).first)
        XCTAssertEqual(pulled.id, attachment.id)
        XCTAssertEqual(pulled.record?.id, record.id)
        XCTAssertEqual(pulled.thumbnailData, thumbnail)

        let pulledURL = AttachmentStore(directory: b.attachmentDirectory)
            .url(forStoredPath: pulled.localPath)
        let pulledBytes = try Data(contentsOf: pulledURL)
        XCTAssertEqual(pulledBytes, bytes, "附件字节经 base64 往返后必须完全一致")
    }

    // MARK: - 4.7 落败版本写入 ConflictLog

    func testConflictLogCreatedOnLose() async throws {
        let (root, a, b) = try makePair()
        defer { try? FileManager.default.removeItem(at: root) }

        let (_, seeded) = try seedPetAndRecord(on: a)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        // B 先改并推送（相对初始版本胜出）
        let bRecord = try XCTUnwrap(try record(withID: seeded.id, on: b))
        try b.recordService.update(
            bRecord, occurredAt: baseTime, title: "日常", note: "B 版本",
            payloadJSON: bRecord.payloadJSON, now: baseTime.addingTimeInterval(50)
        )
        _ = try await b.engine.sync()

        // A 用更晚的时间改并推送，压过 B
        let aRecord = try XCTUnwrap(try record(withID: seeded.id, on: a))
        try a.recordService.update(
            aRecord, occurredAt: baseTime, title: "日常", note: "A 版本",
            payloadJSON: aRecord.payloadJSON, now: baseTime.addingTimeInterval(100)
        )
        _ = try await a.engine.sync()

        // B 拉取后落败
        _ = try await b.engine.sync()

        XCTAssertEqual(aRecord.note, "A 版本")
        XCTAssertEqual(bRecord.note, "A 版本")

        let logs = try b.context.fetch(FetchDescriptor<ConflictLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.entityName, SyncEntityKind.record.rawValue)
        XCTAssertEqual(logs.first?.entityID, seeded.id)
        XCTAssertEqual(logs.first?.winnerDeviceID, "device-A")
        XCTAssertEqual(logs.first?.loserDeviceID, "device-B")
        XCTAssertTrue(
            logs.first?.loserJSON.contains("B 版本") == true,
            "落败版本必须完整保留，便于事后排查"
        )
        XCTAssertTrue(
            try a.context.fetch(FetchDescriptor<ConflictLog>()).isEmpty,
            "胜出一方不应写入冲突日志"
        )
    }
}
