//
//  ReminderRecordSyncTests.swift
//  PawLogTests
//
//  验证记录变更与派生提醒的联动：删除记录清理提醒并撤销通知、修改下次日期重排。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class ReminderRecordSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var center: FakeNotificationCenter!
    private var calendar: Calendar!
    private var now: Date!
    private var pet: Pet!
    private var reminderService: ReminderService!
    private var recordService: RecordService!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        center = FakeNotificationCenter()
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        let notificationService = NotificationService(
            center: center,
            calendar: calendar,
            clock: FixedClock(now)
        )
        reminderService = ReminderService(
            context: context,
            notificationService: notificationService,
            calendar: calendar,
            clock: FixedClock(now)
        )
        recordService = RecordService(context: context, reminderService: reminderService)
        pet = Pet(name: "测试宠物", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        recordService = nil
        reminderService = nil
        center = nil
        pet = nil
        context = nil
        container = nil
        calendar = nil
        now = nil
    }

    private func date(daysFromNow days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    private func makeVaccineRecord(nextDate: Date) throws -> Record {
        try recordService.create(
            pet: pet,
            type: .vaccine,
            occurredAt: now,
            title: "猫三联",
            note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: nextDate))
        )
    }

    // MARK: - 删除

    /// 删除记录必须级联删除派生提醒，并撤销其全部待发通知
    func testDeleteRecordRemovesDerivedReminderAndCancelsNotifications() async throws {
        let record = try makeVaccineRecord(nextDate: date(daysFromNow: 60))
        let reminder = await reminderService.deriveReminder(from: record)
        let reminderID = try XCTUnwrap(reminder?.id)

        XCTAssertEqual(pet.reminders.count, 1)
        XCTAssertEqual(center.pendingCount(for: reminderID), 3)

        try recordService.delete(record)

        XCTAssertTrue(pet.reminders.isEmpty, "删除记录应同时删除派生提醒")
        XCTAssertEqual(center.pendingCount(for: reminderID), 0, "删除记录应撤销该提醒的全部待发通知")
    }

    // MARK: - 更新

    /// 修改下次日期后，派生提醒的 dueAt 更新并重新排期
    func testUpdateNextDateReschedulesReminder() async throws {
        let record = try makeVaccineRecord(nextDate: date(daysFromNow: 30))
        let reminder = await reminderService.deriveReminder(from: record)
        let reminderID = try XCTUnwrap(reminder?.id)

        let newNextDate = date(daysFromNow: 60)
        try recordService.update(
            record,
            occurredAt: now,
            title: "猫三联",
            note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: newNextDate)),
            now: now
        )

        XCTAssertEqual(pet.reminders.count, 1, "更新不应产生重复提醒")
        XCTAssertTrue(calendar.isDate(reminder?.dueAt ?? .distantPast, inSameDayAs: newNextDate))

        // 等重排任务执行后，通知数量仍为 3 且按新日期排期
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(center.pendingCount(for: reminderID), 3)
    }

    /// 清空下次日期后，派生提醒被删除且通知被撤销
    func testUpdateClearingNextDateRemovesReminder() async throws {
        let record = try makeVaccineRecord(nextDate: date(daysFromNow: 60))
        let reminder = await reminderService.deriveReminder(from: record)
        let reminderID = try XCTUnwrap(reminder?.id)
        XCTAssertEqual(center.pendingCount(for: reminderID), 3)

        try recordService.update(
            record,
            occurredAt: now,
            title: "猫三联",
            note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: nil)),
            now: now
        )

        XCTAssertTrue(pet.reminders.isEmpty)
        XCTAssertEqual(center.pendingCount(for: reminderID), 0)
    }

    /// 下次日期未变化时不重复生成提醒
    func testUpdateWithoutNextDateChangeKeepsSingleReminder() async throws {
        let nextDate = date(daysFromNow: 60)
        let record = try makeVaccineRecord(nextDate: nextDate)
        _ = await reminderService.deriveReminder(from: record)

        try recordService.update(
            record,
            occurredAt: now,
            title: "猫三联（改名）",
            note: "备注",
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: nextDate)),
            now: now
        )

        XCTAssertEqual(pet.reminders.count, 1)
    }
}
