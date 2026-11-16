//
//  BackupServiceTests.swift
//  PawLogTests
//
//  备份导出与恢复的主链路：往返一致、导出只读、附件字节一致。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class BackupServiceTests: XCTestCase {

    private var harness: BackupTestHarness!

    override func setUpWithError() throws {
        try super.setUpWithError()
        harness = try BackupTestHarness()
    }

    override func tearDownWithError() throws {
        harness?.cleanup()
        harness = nil
        try super.tearDownWithError()
    }

    // MARK: - 往返一致

    func testExportImportRoundTripPreservesAllModels() async throws {
        let seed = try harness.seed()
        let service = harness.makeService()
        let data = try service.exportData()

        let envelope = try service.decode(data)
        XCTAssertEqual(envelope.version, "1.0")
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.counts.pets, 1)
        XCTAssertEqual(envelope.counts.records, 1)
        XCTAssertEqual(envelope.counts.weightEntries, 1)
        XCTAssertEqual(envelope.counts.reminders, 1)
        XCTAssertEqual(envelope.counts.attachments, 1)

        try harness.emptyEverything()
        let counts = try await service.importBackup(data, overwriteConfirmed: true)
        XCTAssertEqual(counts, envelope.counts)

        let pets = try harness.context.fetch(FetchDescriptor<Pet>())
        XCTAssertEqual(pets.count, 1)
        XCTAssertEqual(pets.first?.name, seed.petName)
        XCTAssertEqual(pets.first?.id, seed.petID)

        let records = try harness.context.fetch(FetchDescriptor<Record>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.occurredAt, seed.occurredAt)
        XCTAssertEqual(records.first?.payloadJSON, seed.payloadJSON)
        XCTAssertEqual(records.first?.id, seed.recordID)
        XCTAssertEqual(records.first?.pet?.id, seed.petID)

        let weights = try harness.context.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(weights.first?.weightKg, 4.5)
        XCTAssertEqual(weights.first?.recordID, seed.recordID)

        let reminders = try harness.context.fetch(FetchDescriptor<Reminder>())
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.dueAt, Date(timeIntervalSince1970: 1_700_200_000))

        let attachments = try harness.context.fetch(FetchDescriptor<Attachment>())
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.id, seed.attachmentID)
        XCTAssertEqual(attachments.first?.thumbnailData, seed.thumbnail)

        // 附件字节完全一致；localPath 只存相对路径，按当前沙箱拼接后可读
        let restoredPath = try XCTUnwrap(attachments.first?.localPath)
        XCTAssertFalse(restoredPath.hasPrefix("/"))
        let restoredURL = AttachmentStore(directory: harness.directory)
            .url(forStoredPath: restoredPath)
        let restoredBytes = try Data(contentsOf: restoredURL)
        XCTAssertEqual(restoredBytes, seed.fileBytes)
    }

    func testAttachmentBase64RoundTripIsByteIdentical() throws {
        let seed = try harness.seed()
        let envelope = try harness.makeService().makeBackup()
        let dto = try XCTUnwrap(envelope.attachments.first)

        let original = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(dto.fileDataBase64)))
        XCTAssertEqual(original, seed.fileBytes)

        let thumb = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(dto.thumbnailDataBase64)))
        XCTAssertEqual(thumb, seed.thumbnail)
    }

    func testExportDoesNotModifyExistingData() throws {
        try harness.seed()
        let service = harness.makeService()
        let before = try service.existingCounts()

        _ = try service.exportData()
        _ = try service.makeBackup()

        let after = try service.existingCounts()
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.records, 1)
    }

    func testBackupFileNameFollowsPattern() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let name = BackupService.fileName(for: date)

        XCTAssertTrue(name.hasPrefix("pawlog-backup-"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertEqual(name.count, "pawlog-backup-yyyyMMdd-HHmm.json".count)
    }
}
