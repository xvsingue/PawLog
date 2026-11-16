//
//  ReminderServiceTests.swift
//  PawLogTests
//
//  验证提醒派生规则、重复规则生成、开关撤销通知、分组查询。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class ReminderServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var recordService: RecordService!
    private var reminderService: ReminderService!
    private var center: FakeNotificationCenter!
    private var pet: Pet!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
            configurations: config
        )
        context = container.mainContext
        center = FakeNotificationCenter()
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        let notif = NotificationService(center: center, calendar: calendar, clock: FixedClock(now))
        recordService = RecordService(context: context)
        reminderService = ReminderService(
            context: context,
            notificationService: notif,
            calendar: calendar,
            clock: FixedClock(now)
        )
        pet = Pet(name: "测试宠物", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        reminderService = nil
        recordService = nil
        center = nil
        pet = nil
        context = nil
        container = nil
        calendar = nil
    }

    private func date(daysFromNow days: Int, now: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    // MARK: - 派生规则

    /// 疫苗记录带 nextDate → 派生疫苗提醒，dueAt = nextDate，sourceRecordID 关联
    func testDeriveVaccineCreatesReminder() async throws {
        let now = Date()
        let next = date(daysFromNow: 30, now: now)
        let record = try recordService.create(
            pet: pet,
            type: .vaccine,
            occurredAt: now,
            title: "猫三联",
            note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: next))
        )

        let reminder = await reminderService.deriveReminder(from: record)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .vaccine)
        XCTAssertTrue(calendar.isDate(reminder?.dueAt ?? .distantPast, inSameDayAs: next))
        XCTAssertEqual(reminder?.sourceRecordID, record.id)
        XCTAssertEqual(pet.reminders.count, 1)
    }

    /// 驱虫 / 用药 / 就诊各自派生对应类型提醒
    func testDeriveDewormingMedicationVisit() async throws {
        let now = Date()

        let deworming = try recordService.create(
            pet: pet, type: .deworming, occurredAt: now, title: "体内外", note: nil,
            payloadJSON: PayloadCoding.encode(DewormingPayload(scope: .both, nextDate: date(daysFromNow: 90, now: now)))
        )
        let medication = try recordService.create(
            pet: pet, type: .medication, occurredAt: now, title: "阿莫西林", note: nil,
            payloadJSON: PayloadCoding.encode(MedicationPayload(
                drugName: "阿莫西林", dosage: "50mg", frequency: "每日两次",
                endDate: date(daysFromNow: 7, now: now)
            ))
        )
        let visit = try recordService.create(
            pet: pet, type: .visit, occurredAt: now, title: "复诊", note: nil,
            payloadJSON: PayloadCoding.encode(VisitPayload(hospital: "康宁", followUpDate: date(daysFromNow: 14, now: now)))
        )

        let r1 = await reminderService.deriveReminder(from: deworming)
        let r2 = await reminderService.deriveReminder(from: medication)
        let r3 = await reminderService.deriveReminder(from: visit)

        XCTAssertEqual(r1?.kind, .deworming)
        XCTAssertEqual(r2?.kind, .medication)
        XCTAssertEqual(r3?.kind, .visit)
        XCTAssertEqual(pet.reminders.count, 3)
    }

    /// 无下次日期的记录不派生提醒
    func testDeriveWithoutNextDateReturnsNil() async throws {
        let now = Date()
        let record = try recordService.create(
            pet: pet, type: .vaccine, occurredAt: now, title: "猫三联", note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联"))
        )

        let reminder = await reminderService.deriveReminder(from: record)

        XCTAssertNil(reminder)
        XCTAssertEqual(pet.reminders.count, 0)
    }

    /// 症状 / 体重 / 日常不派生提醒
    func testDeriveSymptomWeightDailyNoReminder() async throws {
        let now = Date()
        for type in [RecordType.symptom, .weight, .daily] {
            let record = try recordService.create(
                pet: pet, type: type, occurredAt: now, title: "测试", note: nil,
                payloadJSON: PayloadCoding.encode(SymptomPayload(symptomType: .vomit, severity: 1))
            )
            let reminder = await reminderService.deriveReminder(from: record)
            XCTAssertNil(reminder, "\(type) 不应派生提醒")
        }
        XCTAssertEqual(pet.reminders.count, 0)
    }

    /// 同一记录多次派生只保留一条提醒（upsert），且 dueAt 被更新
    func testDeriveUpsertsBySourceRecordID() async throws {
        let now = Date()
        let next1 = date(daysFromNow: 30, now: now)
        let record = try recordService.create(
            pet: pet, type: .vaccine, occurredAt: now, title: "猫三联", note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: next1))
        )

        _ = await reminderService.deriveReminder(from: record)
        XCTAssertEqual(pet.reminders.count, 1)

        // 修改 nextDate 后再次派生
        let next2 = date(daysFromNow: 60, now: now)
        try recordService.update(
            record, occurredAt: now, title: "猫三联", note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: next2))
        )
        let updated = await reminderService.deriveReminder(from: record)

        XCTAssertEqual(pet.reminders.count, 1, "同一记录只应保留一条提醒")
        XCTAssertTrue(calendar.isDate(updated?.dueAt ?? .distantPast, inSameDayAs: next2))
    }

    // MARK: - 重复规则

    /// 标记完成且有重复规则时，dueAt 推进到下一次
    func testMarkDoneWithMonthlyAdvancesDueAt() async throws {
        let dueAt = date(daysFromNow: 30, now: now)
        let reminder = Reminder(pet: pet, kind: .vaccine, sourceRecordID: nil, dueAt: dueAt, repeatRule: .monthly, enabled: true)
        context.insert(reminder)
        try context.save()

        try await reminderService.markDone(reminder)

        let expected = calendar.date(byAdding: .month, value: 1, to: now)
        XCTAssertEqual(reminder.dueAt, expected)
        XCTAssertEqual(reminder.lastDoneAt, now)
        XCTAssertTrue(reminder.enabled)
    }

    /// 无重复规则时，标记完成后关闭提醒
    func testMarkDoneNoneDisablesReminder() async throws {
        let reminder = Reminder(pet: pet, kind: .vaccine, dueAt: date(daysFromNow: 30, now: now), repeatRule: .none, enabled: true)
        context.insert(reminder)
        try context.save()

        try await reminderService.markDone(reminder)

        XCTAssertFalse(reminder.enabled, "一次性提醒完成后应关闭")
        XCTAssertEqual(reminder.lastDoneAt, now)
    }

    // MARK: - 分组查询

    /// 即将到期 / 已过期分组正确
    func testFetchGroupsUpcomingAndOverdue() throws {
        let upcoming = Reminder(pet: pet, kind: .vaccine, dueAt: date(daysFromNow: 5, now: now), enabled: true)
        let today = Reminder(pet: pet, kind: .deworming, dueAt: calendar.startOfDay(for: now), enabled: true)
        let overdue = Reminder(pet: pet, kind: .visit, dueAt: date(daysFromNow: -3, now: now), enabled: true)
        let disabled = Reminder(pet: pet, kind: .medication, dueAt: date(daysFromNow: 10, now: now), enabled: false)
        [upcoming, today, overdue, disabled].forEach { context.insert($0) }
        try context.save()

        let groups = reminderService.fetchReminders(for: pet)

        XCTAssertEqual(groups.upcoming.count, 2)
        XCTAssertTrue(groups.upcoming.contains { $0.id == upcoming.id })
        XCTAssertTrue(groups.upcoming.contains { $0.id == today.id })
        XCTAssertEqual(groups.overdue.count, 1)
        XCTAssertEqual(groups.overdue.first?.id, overdue.id)
    }

    // MARK: - 开关

    /// 关闭开关后该提醒的 pending 通知数为 0
    func testSetEnabledFalseCancelsNotifications() async throws {
        let record = try recordService.create(
            pet: pet, type: .vaccine, occurredAt: now, title: "猫三联", note: nil,
            payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: date(daysFromNow: 60, now: now)))
        )
        let reminder = await reminderService.deriveReminder(from: record)
        let reminderID = try XCTUnwrap(reminder?.id)
        XCTAssertEqual(center.pendingCount(for: reminderID), 3)

        try await reminderService.setEnabled(reminder!, enabled: false)

        XCTAssertEqual(center.pendingCount(for: reminderID), 0, "关闭开关后 pending 数应为 0")
    }
}
