//
//  BackupImportValidationTests.swift
//  PawLogTests
//
//  备份导入的拒绝路径：版本不兼容、结构损坏、base64 非法，
//  以及每种失败都不得破坏现有数据。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class BackupImportValidationTests: XCTestCase {

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

    // MARK: - 版本

    func testVersionTooNewIsRejected() throws {
        let service = harness.makeService()
        let data = try harness.mutatedExport { $0["version"] = "2.1" }

        XCTAssertThrowsError(try service.decode(data)) { error in
            guard let backupError = error as? BackupError,
                  case let .versionTooNew(file, supported) = backupError else {
                return XCTFail("应抛出版本过高错误，实际：\(error)")
            }
            XCTAssertEqual(file, "2.1")
            XCTAssertEqual(supported, "1.0")
            XCTAssertTrue(error.localizedDescription.contains("2.1"))
        }
    }

    func testVersionTooOldIsRejected() throws {
        let service = harness.makeService()
        let data = try harness.mutatedExport { $0["version"] = "0.9" }

        XCTAssertThrowsError(try service.decode(data)) { error in
            guard let backupError = error as? BackupError,
                  case .versionTooOld = backupError else {
                return XCTFail("应抛出版本过低错误，实际：\(error)")
            }
        }
    }

    func testSchemaVersionMismatchIsRejected() throws {
        let service = harness.makeService()
        let data = try harness.mutatedExport { $0["schemaVersion"] = 99 }

        XCTAssertThrowsError(try service.decode(data)) { error in
            guard let backupError = error as? BackupError,
                  case .schemaVersionMismatch = backupError else {
                return XCTFail("应抛出 schema 不一致错误，实际：\(error)")
            }
        }
    }

    func testCountsMismatchIsRejected() throws {
        try harness.seed()
        let service = harness.makeService()
        let data = try harness.mutatedExport {
            $0["counts"] = ["pets": 9, "records": 9, "weightEntries": 9,
                            "reminders": 9, "attachments": 9]
        }

        XCTAssertThrowsError(try service.decode(data)) { error in
            guard let backupError = error as? BackupError,
                  case .malformed = backupError else {
                return XCTFail("应抛出结构损坏错误，实际：\(error)")
            }
        }
    }

    // MARK: - 损坏文件不破坏现有数据

    func testTruncatedJSONThrowsAndKeepsData() async throws {
        try harness.seed()
        let service = harness.makeService()
        let data = try service.exportData()
        let truncated = Data(data.prefix(data.count / 2))

        let before = try service.existingCounts()
        do {
            _ = try await service.importBackup(truncated, overwriteConfirmed: true)
            XCTFail("截断的 JSON 应被拒绝")
        } catch {
            XCTAssertTrue(error is BackupError)
        }
        XCTAssertEqual(try service.existingCounts(), before)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<Pet>()).count, 1)
    }

    func testMissingFieldThrowsAndKeepsData() async throws {
        try harness.seed()
        let service = harness.makeService()
        let data = try harness.mutatedExport { $0.removeValue(forKey: "pets") }

        let before = try service.existingCounts()
        do {
            _ = try await service.importBackup(data, overwriteConfirmed: true)
            XCTFail("缺字段的 JSON 应被拒绝")
        } catch {
            XCTAssertTrue(error is BackupError)
        }
        XCTAssertEqual(try service.existingCounts(), before)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<Pet>()).count, 1)
    }

    func testInvalidBase64ThrowsAndKeepsData() async throws {
        try harness.seed()
        let service = harness.makeService()
        let data = try harness.mutatedExport { dict in
            guard var attachments = dict["attachments"] as? [[String: Any]],
                  var first = attachments.first else { return }
            first["fileDataBase64"] = "@@@not-base64@@@"
            attachments[0] = first
            dict["attachments"] = attachments
        }

        let before = try service.existingCounts()
        do {
            _ = try await service.importBackup(data, overwriteConfirmed: true)
            XCTFail("非法 base64 应被拒绝")
        } catch {
            guard let backupError = error as? BackupError,
                  case .malformed = backupError else {
                return XCTFail("应抛出结构损坏错误，实际：\(error)")
            }
        }
        XCTAssertEqual(try service.existingCounts(), before)
    }

    func testOverwriteRequiresConfirmation() async throws {
        try harness.seed()
        let service = harness.makeService()
        let data = try service.exportData()

        do {
            _ = try await service.importBackup(data)
            XCTFail("已有数据时应要求确认")
        } catch {
            guard let backupError = error as? BackupError,
                  case let .overwriteNotConfirmed(count) = backupError else {
                return XCTFail("应要求确认覆盖，实际：\(error)")
            }
            XCTAssertEqual(count, 1)
        }
        XCTAssertEqual(try service.existingCounts().records, 1)
    }
}
