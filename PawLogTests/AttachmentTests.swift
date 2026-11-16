//
//  AttachmentTests.swift
//  PawLogTests
//
//  M10 照片附件：压缩上限、缩略图、相对路径、3 张上限、墓碑与清理、
//  备份往返字节一致、列表异步解码。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class AttachmentTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var directory: URL!
    private var petService: PetService!
    private var recordService: RecordService!
    private var attachmentService: AttachmentService!

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PawLogAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let clock = FixedClock(now)
        petService = PetService(context: context, deviceID: "device-test", clock: clock,
                                attachmentDirectory: directory)
        recordService = RecordService(context: context, deviceID: "device-test", clock: clock,
                                      attachmentDirectory: directory)
        attachmentService = AttachmentService(context: context, attachmentDirectory: directory,
                                              deviceID: "device-test", clock: clock)
    }

    override func tearDownWithError() throws {
        attachmentService = nil
        recordService = nil
        petService = nil
        context = nil
        container = nil
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 工具

    private func makeRecord() throws -> Record {
        let pet = Pet(name: "咪咪", species: .cat)
        try petService.createPet(pet)
        return try recordService.create(
            pet: pet,
            type: .visit,
            occurredAt: now,
            title: "复查",
            note: nil,
            payloadJSON: "",
            now: now
        )
    }

    // MARK: - 5.1 压缩上限

    func testCompressedImageWithinPixelLimitAndReasonableSize() throws {
        let original = try AttachmentTestSupport.makeJPEG(width: 3000, height: 2000)
        let store = AttachmentStore(directory: directory)
        let stored = try store.saveImage(original, recordID: UUID())
        let written = try Data(contentsOf: store.url(forStoredPath: stored.relativePath))

        let size = try AttachmentTestSupport.pixelSize(of: written)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1600, "主图长边不得超过 1600")
        XCTAssertLessThan(written.count, 3_000_000, "压缩后体积应在合理上限内")
        XCTAssertEqual(written.prefix(2), Data([0xFF, 0xD8]), "主图必须是 JPEG")
    }

    // MARK: - 5.2 缩略图

    func testThumbnailLongEdgeWithinLimit() throws {
        let original = try AttachmentTestSupport.makeJPEG(width: 3000, height: 2000)
        let store = AttachmentStore(directory: directory)
        let stored = try store.saveImage(original, recordID: UUID())
        let thumbnail = try XCTUnwrap(stored.thumbnailData)
        let size = try AttachmentTestSupport.pixelSize(of: thumbnail)

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 200, "缩略图长边不得超过 200")
        XCTAssertNotNil(AttachmentImageDecoder.decode(data: thumbnail, maxPixelSize: 200))
    }

    // MARK: - 5.3 相对路径

    func testStoredPathIsRelativeAndReconstructable() async throws {
        let record = try makeRecord()
        let attachment = try await attachmentService.addImage(
            try AttachmentTestSupport.makeJPEG(width: 1200, height: 800),
            to: record
        )

        XCTAssertFalse(attachment.localPath.hasPrefix("/"), "localPath 不得是绝对路径")
        XCTAssertFalse(attachment.localPath.contains(directory.path), "不得写入沙箱绝对路径")
        XCTAssertTrue(attachment.localPath.hasPrefix("attachments/\(record.id.uuidString)/"))
        XCTAssertTrue(attachment.localPath.hasSuffix(".jpg"))

        let url = attachmentService.fileURL(for: attachment)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(attachment.thumbnailData)
    }

    // MARK: - 5.4 超过 3 张拒绝且不落文件

    func testFourthAttachmentRejectedWithoutWritingFiles() async throws {
        let record = try makeRecord()
        let image = try AttachmentTestSupport.makeJPEG(width: 1200, height: 800)
        for _ in 0..<AttachmentService.maxPerRecord {
            _ = try await attachmentService.addImage(image, to: record)
        }
        let filesBefore = AttachmentTestSupport.storedFileCount(in: directory)

        do {
            _ = try await attachmentService.addImage(image, to: record)
            XCTFail("第 4 张应被拒绝")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .limitReached)
        }

        XCTAssertEqual(attachmentService.attachments(for: record).count, AttachmentService.maxPerRecord)
        XCTAssertEqual(AttachmentTestSupport.storedFileCount(in: directory), filesBefore, "被拒绝的照片不得写入文件")
    }

    // MARK: - 5.5 墓碑级联与清理

    func testRecordTombstoneCascadesToAttachmentThenPurgerRemovesFile() async throws {
        let oldNow = now.addingTimeInterval(-40 * 86_400)
        let oldClock = FixedClock(oldNow)
        let oldPetService = PetService(context: context, deviceID: "device-test", clock: oldClock,
                                       attachmentDirectory: directory)
        let oldRecordService = RecordService(context: context, deviceID: "device-test", clock: oldClock,
                                             attachmentDirectory: directory)
        let oldAttachmentService = AttachmentService(context: context, attachmentDirectory: directory,
                                                     deviceID: "device-test", clock: oldClock)

        let pet = Pet(name: "咪咪", species: .cat)
        try oldPetService.createPet(pet)
        let record = try oldRecordService.create(
            pet: pet, type: .visit, occurredAt: oldNow, title: "复查",
            note: nil, payloadJSON: "", now: oldNow
        )
        let attachment = try await oldAttachmentService.addImage(
            try AttachmentTestSupport.makeJPEG(width: 1200, height: 800), to: record
        )
        let fileURL = oldAttachmentService.fileURL(for: attachment)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try oldRecordService.delete(record)
        XCTAssertNotNil(attachment.deletedAt, "删除记录时附件必须一并墓碑化")

        let purger = TombstonePurger(
            context: context,
            clock: FixedClock(now),
            attachmentDirectory: directory
        )
        // 未同步：不清理，文件保留
        XCTAssertEqual(try purger.purge(), .zero)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        for log in try context.fetch(FetchDescriptor<ChangeLog>()) { log.synced = true }
        try context.save()

        let result = try purger.purge()
        XCTAssertEqual(result.attachments, 1)
        XCTAssertEqual(result.records, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Attachment>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "清理后磁盘文件必须删除")
    }

    // MARK: - 5.6 备份往返

    func testBackupRoundTripPreservesAttachmentBytes() async throws {
        let record = try makeRecord()
        let attachment = try await attachmentService.addImage(
            try AttachmentTestSupport.makeJPEG(width: 2400, height: 1600), to: record
        )
        let storedBytes = try Data(contentsOf: attachmentService.fileURL(for: attachment))
        let thumbnail = try XCTUnwrap(attachment.thumbnailData)

        let backup = BackupService(
            context: context,
            clock: FixedClock(now),
            attachmentDirectory: directory
        )
        let envelope = try backup.makeBackup()
        let dto = try XCTUnwrap(envelope.attachments.first)
        XCTAssertFalse(dto.localPath.hasPrefix("/"))
        XCTAssertEqual(
            Data(base64Encoded: try XCTUnwrap(dto.fileDataBase64)),
            storedBytes,
            "备份内照片字节必须完整"
        )
        let data = try backup.exportData()

        // 模拟换设备：清空数据与磁盘文件后恢复
        try ModelCleanup.deleteBusinessData(in: context)
        try context.save()
        try FileManager.default.removeItem(at: directory)

        _ = try await backup.importBackup(data, overwriteConfirmed: true)

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<Attachment>()).first)
        XCTAssertFalse(restored.localPath.hasPrefix("/"), "恢复后仍只存相对路径")
        let restoredURL = AttachmentStore(directory: directory).url(forStoredPath: restored.localPath)
        let restoredBytes = try Data(contentsOf: restoredURL)
        XCTAssertEqual(restoredBytes, storedBytes, "恢复后照片字节必须一致")
        XCTAssertEqual(restored.thumbnailData, thumbnail)
        XCTAssertNotNil(AttachmentImageDecoder.decode(data: restoredBytes, maxPixelSize: 1600))
    }

    // MARK: - 5.7 列表异步解码

    func testThumbnailDecodingIsOffloadedToDetachedTask() async throws {
        let data = try AttachmentTestSupport.makeJPEG(width: 2400, height: 1600)
        let recorder = ThreadRecorder()

        let task = AttachmentThumbnailLoader.makeTask(
            data: data,
            maxPixelSize: AttachmentStore.maxThumbnailPixelSize
        ) { isMain in
            recorder.record(isMain)
        }
        let value = await task.value
        let decoded = try XCTUnwrap(value)

        XCTAssertFalse(recorder.ranOnMainThread, "缩略图解码必须发生在后台队列")
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 200)
    }
}

/// 跨并发域记录解码线程
nonisolated private final class ThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var isMain: Bool?

    func record(_ isMain: Bool) {
        lock.lock()
        self.isMain = isMain
        lock.unlock()
    }

    var ranOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        // 没被调用时按主线程处理，避免测试假通过
        return isMain ?? true
    }
}
