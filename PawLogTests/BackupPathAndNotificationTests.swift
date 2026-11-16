//
//  BackupPathAndNotificationTests.swift
//  PawLogTests
//
//  备份中的附件只存相对路径；跨设备恢复按当前沙箱重拼；
//  导入成功后按当前提醒重排通知。
//

import XCTest
import SwiftData
import UserNotifications
@testable import PawLog

@MainActor
final class BackupPathAndNotificationTests: XCTestCase {

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

    // MARK: - 相对路径

    func testExportedAttachmentPathIsRelative() throws {
        try harness.seed()
        let envelope = try harness.makeService().makeBackup()
        let dto = try XCTUnwrap(envelope.attachments.first)

        XCTAssertFalse(dto.localPath.hasPrefix("/"), "备份内不得出现绝对路径")
        XCTAssertEqual(dto.localPath, "attachments/sample.pdf")
    }

    func testImportRewritesForeignSandboxPath() async throws {
        let seed = try harness.seed()
        let service = harness.makeService()
        let data = try service.exportData()

        // 模拟另一台设备：路径换成不存在的沙箱绝对路径
        let foreign = "/var/mobile/Containers/Data/Application/00000000-1111-2222-3333-444444444444/Documents/attachments/sample.pdf"
        let mutated = try harness.mutatedExport { dict in
            guard var attachments = dict["attachments"] as? [[String: Any]],
                  var first = attachments.first else { return }
            first["localPath"] = foreign
            attachments[0] = first
            dict["attachments"] = attachments
        }

        try harness.emptyEverything()
        _ = try await service.importBackup(mutated, overwriteConfirmed: true)

        let attachments = try harness.context.fetch(FetchDescriptor<Attachment>())
        let restored = try XCTUnwrap(attachments.first)

        XCTAssertFalse(restored.localPath.contains("Application/00000000"), "不得沿用外来绝对路径")
        XCTAssertEqual(
            restored.localPath,
            harness.directory.appendingPathComponent("sample.pdf").path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.localPath))

        let bytes = try Data(contentsOf: URL(fileURLWithPath: restored.localPath))
        XCTAssertEqual(bytes, seed.fileBytes)
    }

    // MARK: - 通知重排

    func testImportReschedulesThreeEnabledReminders() async throws {
        try harness.seedReminders(count: 3)
        let service = harness.makeService()
        let data = try service.exportData()
        try harness.emptyEverything()

        _ = try await service.importBackup(data, overwriteConfirmed: true)

        let pending = await harness.center.getPendingNotificationRequests()
        let reminderOnly = pending.filter {
            !$0.identifier.hasPrefix(NotificationService.overdueSummaryPrefix)
                && !$0.identifier.hasSuffix("-snooze")
        }
        XCTAssertEqual(reminderOnly.count, 3, "3 条启用提醒各排 1 条提前通知")
    }

    func testImportWithZeroRemindersClearsPending() async throws {
        try harness.seedReminders(count: 3)
        let service = harness.makeService()
        let withReminders = try service.exportData()
        try harness.emptyEverything()
        _ = try await service.importBackup(withReminders, overwriteConfirmed: true)
        var pending = await harness.center.getPendingNotificationRequests()
        XCTAssertEqual(reminderNotificationCount(pending), 3)

        // 再导入一份没有提醒的备份
        let withoutReminders = try harness.mutatedExport { dict in
            dict["reminders"] = []
            guard var counts = dict["counts"] as? [String: Any] else { return }
            counts["reminders"] = 0
            dict["counts"] = counts
        }
        _ = try await service.importBackup(withoutReminders, overwriteConfirmed: true)

        pending = await harness.center.getPendingNotificationRequests()
        XCTAssertEqual(reminderNotificationCount(pending), 0)
    }

    /// 只统计提醒本身的提前通知，排除逾期汇总与稍后提醒
    private func reminderNotificationCount(_ requests: [UNNotificationRequest]) -> Int {
        requests.filter {
            !$0.identifier.hasPrefix(NotificationService.overdueSummaryPrefix)
                && !$0.identifier.hasSuffix("-snooze")
        }.count
    }
}
