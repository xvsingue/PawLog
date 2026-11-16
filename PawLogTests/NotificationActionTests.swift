//
//  NotificationActionTests.swift
//  PawLogTests
//
//  通知动作回调写回、稍后提醒、逾期每日汇总不重复。
//

import XCTest
import SwiftData
import UserNotifications
@testable import PawLog

@MainActor
final class NotificationActionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var center: FakeNotificationCenter!
    private var calendar: Calendar!
    private var now: Date!
    private var pet: Pet!
    private var notificationService: NotificationService!
    private var reminderService: ReminderService!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            configurations: config
        )
        context = container.mainContext
        center = FakeNotificationCenter()
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        notificationService = NotificationService(
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
        pet = Pet(name: "咪咪", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        reminderService = nil
        notificationService = nil
        center = nil
        pet = nil
        context = nil
        container = nil
        calendar = nil
        now = nil
    }

    private func makeReminder(dueDays: Int, rule: RepeatRule = .none) throws -> Reminder {
        let due = calendar.date(byAdding: .day, value: dueDays, to: now)!
        let reminder = Reminder(pet: pet, kind: .vaccine, dueAt: due, repeatRule: rule, enabled: true)
        context.insert(reminder)
        try context.save()
        return reminder
    }

    // MARK: - 动作映射

    func testActionIdentifierMapping() {
        XCTAssertEqual(ReminderNotificationAction(identifier: "REMINDER_DONE"), .done)
        XCTAssertEqual(ReminderNotificationAction(identifier: "REMINDER_SNOOZE"), .snooze)
        XCTAssertNil(ReminderNotificationAction(identifier: "UNKNOWN"))
    }

    // MARK: - 标记完成写回

    /// 「标记完成」写入 lastDoneAt 并按 repeatRule 生成下一次
    func testDoneActionWritesLastDoneAtAndReschedules() async throws {
        let reminder = try makeReminder(dueDays: 10, rule: .monthly)

        await ReminderActionHandler.perform(
            .done,
            reminderID: reminder.id,
            context: context,
            notificationService: notificationService,
            calendar: calendar,
            clock: FixedClock(now)
        )

        XCTAssertEqual(reminder.lastDoneAt, now)
        XCTAssertTrue(reminder.enabled)
        XCTAssertEqual(
            reminder.dueAt,
            calendar.date(byAdding: .month, value: 1, to: now),
            "按月重复应推进到下一次"
        )
        XCTAssertGreaterThan(center.pendingCount(for: reminder.id), 0, "完成后应重新排期")
    }

    /// 「稍后提醒」延后 1 天且只排一条
    func testSnoozeActionSchedulesOneDayLater() async throws {
        let reminder = try makeReminder(dueDays: 3)

        await ReminderActionHandler.perform(
            .snooze,
            reminderID: reminder.id,
            context: context,
            notificationService: notificationService,
            calendar: calendar,
            clock: FixedClock(now)
        )

        let id = notificationService.snoozeID(reminderID: reminder.id)
        let request = try XCTUnwrap(center.requests[id])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        let expected = calendar.date(byAdding: .day, value: ReminderActionHandler.snoozeDays, to: now)!
        XCTAssertEqual(trigger.dateComponents.day, calendar.component(.day, from: expected))
        XCTAssertEqual(trigger.dateComponents.hour, calendar.component(.hour, from: expected))
    }

    // MARK: - 逾期汇总

    /// 逾期汇总每天最多 1 条，重复调用不叠加
    func testOverdueSummaryIsUniquePerDay() async {
        await notificationService.scheduleOverdueSummary(overdueCount: 2)
        let firstPass = Set(center.requests.keys.filter { $0.hasPrefix(NotificationService.overdueSummaryPrefix) })

        await notificationService.scheduleOverdueSummary(overdueCount: 2)
        let secondPass = Set(center.requests.keys.filter { $0.hasPrefix(NotificationService.overdueSummaryPrefix) })

        XCTAssertFalse(firstPass.isEmpty, "存在逾期时应排汇总")
        XCTAssertLessThanOrEqual(firstPass.count, NotificationService.overdueSummaryDays)
        XCTAssertEqual(firstPass, secondPass, "重复对账不应叠加汇总通知")
    }

    /// 没有逾期提醒时不排汇总
    func testNoOverdueSummaryWhenCountIsZero() async {
        await notificationService.scheduleOverdueSummary(overdueCount: 0)
        XCTAssertEqual(center.overdueSummaryCount, 0)
    }

    /// 逾期汇总在 09:00 触发，不与静默时段冲突
    func testOverdueSummaryFiresAtNine() async throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let service = NotificationService(center: center, calendar: calendar, clock: FixedClock(base))
        await service.scheduleOverdueSummary(overdueCount: 1)

        let firstID = service.overdueSummaryID(
            for: calendar.date(from: DateComponents(year: 2026, month: 11, day: 17))!
        )
        let request = try XCTUnwrap(center.requests[firstID])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, NotificationService.overdueSummaryHour)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }
}
