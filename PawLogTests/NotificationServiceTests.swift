//
//  NotificationServiceTests.swift
//  PawLogTests
//
//  验证通知 id 唯一性、30/7/1 排期、过期偏移跳过、撤销、reconcile 幂等与清理。
//

import XCTest
import UserNotifications
@testable import PawLog

final class NotificationServiceTests: XCTestCase {
    private var center: FakeNotificationCenter!
    private var service: NotificationService!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        center = FakeNotificationCenter()
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        service = NotificationService(center: center, calendar: calendar, clock: FixedClock(now))
    }

    override func tearDownWithError() throws {
        center = nil
        service = nil
        calendar = nil
        now = nil
    }

    private func date(daysFromNow days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    // MARK: - id 唯一性

    /// 不同提醒或不同偏移生成的 id 必须互不相同
    func testNotificationIDIsUniqueByReminderAndOffset() {
        let a = UUID()
        let b = UUID()
        let ids: Set<String> = [
            service.notificationID(reminderID: a, offsetDays: 30),
            service.notificationID(reminderID: a, offsetDays: 7),
            service.notificationID(reminderID: a, offsetDays: 1),
            service.notificationID(reminderID: b, offsetDays: 30),
            service.notificationID(reminderID: b, offsetDays: 7),
            service.notificationID(reminderID: b, offsetDays: 1)
        ]
        XCTAssertEqual(ids.count, 6, "6 个 id 应互不相同")
    }

    // MARK: - 排期

    /// 到期日足够远时，30/7/1 三个偏移全部排期
    func testScheduleCreatesThreeNotificationsForFarDueDate() async {
        let reminder = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 60))

        await service.schedule(for: reminder)

        XCTAssertEqual(center.requests.count, 3)
        for offset in NotificationService.leadDays {
            let id = service.notificationID(reminderID: reminder.id, offsetDays: offset)
            XCTAssertNotNil(center.requests[id], "偏移 \(offset) 的通知应已排期")
        }
    }

    /// 已过期的偏移不排期；仅排仍在未来的偏移
    func testScheduleSkipsExpiredOffsets() async {
        // 10 天后到期：30 天偏移已过，7/1 天仍在未来
        let reminder = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 10))

        await service.schedule(for: reminder)

        XCTAssertEqual(center.requests.count, 2)
        XCTAssertNil(center.requests[service.notificationID(reminderID: reminder.id, offsetDays: 30)])
        XCTAssertNotNil(center.requests[service.notificationID(reminderID: reminder.id, offsetDays: 7)])
        XCTAssertNotNil(center.requests[service.notificationID(reminderID: reminder.id, offsetDays: 1)])
    }

    // MARK: - 撤销

    /// cancel 撤销某提醒的全部待发通知
    func testCancelRemovesAllNotificationsForReminder() async {
        let reminder = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 60))
        await service.schedule(for: reminder)
        XCTAssertEqual(center.pendingCount(for: reminder.id), 3)

        service.cancel(for: reminder.id)

        XCTAssertEqual(center.pendingCount(for: reminder.id), 0)
        XCTAssertEqual(center.requests.count, 0)
    }

    // MARK: - reconcile

    /// reconcile 幂等：连续执行两次 pending 数不变
    func testReconcileIsIdempotent() async {
        let reminder = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 60), enabled: true)

        await service.reconcile(reminders: [reminder])
        let firstCount = center.requests.count

        await service.reconcile(reminders: [reminder])
        let secondCount = center.requests.count

        XCTAssertEqual(firstCount, 3)
        XCTAssertEqual(firstCount, secondCount, "第二次 reconcile 不应改变 pending 数")
    }

    /// reconcile 清理不属于任何启用提醒的多余通知
    func testReconcileRemovesStaleNotifications() async {
        let staleReminder = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 60), enabled: true)
        await service.schedule(for: staleReminder)
        XCTAssertEqual(center.requests.count, 3)

        // 对账时传入空提醒列表 → 全部 pending 应被清理
        await service.reconcile(reminders: [])

        XCTAssertEqual(center.requests.count, 0)
    }

    /// reconcile 补齐已被手动删除的缺失通知
    func testReconcileFillsMissingNotifications() async {
        let reminder = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 60), enabled: true)
        await service.schedule(for: reminder)
        XCTAssertEqual(center.requests.count, 3)

        // 手动删掉一个偏移的通知
        let removedID = service.notificationID(reminderID: reminder.id, offsetDays: 7)
        center.removePendingNotificationRequests(withIdentifiers: [removedID])
        XCTAssertEqual(center.requests.count, 2)

        await service.reconcile(reminders: [reminder])

        XCTAssertEqual(center.requests.count, 3, "reconcile 应补齐被删除的通知")
        XCTAssertNotNil(center.requests[removedID])
    }

    /// 关闭的提醒不排期，且其旧通知被 reconcile 清理
    func testReconcileSkipsDisabledReminders() async {
        let disabled = Reminder(kind: .vaccine, dueAt: date(daysFromNow: 60), enabled: false)
        await service.schedule(for: disabled)
        // schedule 本身不看 enabled，仍会排 3 条
        XCTAssertEqual(center.requests.count, 3)

        await service.reconcile(reminders: [disabled])

        XCTAssertEqual(center.requests.count, 0, "已关闭提醒的通知应被清理")
    }

    // MARK: - 静默时段（22:00–08:00）

    private func fixedService(at date: Date) -> NotificationService {
        NotificationService(center: center, calendar: calendar, clock: FixedClock(date))
    }

    /// 触发时间在 22:00 之后，顺延到次日 08:00
    func testFireTimeAfter22ShiftsToNextMorning() async throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let service = fixedService(at: base)
        let dueAt = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 23))!
        let reminder = Reminder(kind: .vaccine, dueAt: dueAt)

        await service.schedule(for: reminder)

        // 30 天偏移已过期，只剩 7 天与 1 天两条
        XCTAssertEqual(center.requests.count, 2)
        let id = service.notificationID(reminderID: reminder.id, offsetDays: 7)
        let request = try XCTUnwrap(center.requests[id])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.day, 24, "22:00 触发应顺延到次日")
        XCTAssertEqual(trigger.dateComponents.hour, 8)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    /// 触发时间在 08:00 之前，顺延到当日 08:00
    func testFireTimeBefore8ShiftsToSameDayMorning() async throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let service = fixedService(at: base)
        let dueAt = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 5))!
        let reminder = Reminder(kind: .vaccine, dueAt: dueAt)

        await service.schedule(for: reminder)

        let id = service.notificationID(reminderID: reminder.id, offsetDays: 7)
        let request = try XCTUnwrap(center.requests[id])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.day, 17, "08:00 前触发应顺延到当日 08:00")
        XCTAssertEqual(trigger.dateComponents.hour, 8)
    }

    /// 白天触发时间保持原样
    func testFireTimeInDaytimeIsUnchanged() async throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let service = fixedService(at: base)
        let dueAt = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 15))!
        let reminder = Reminder(kind: .vaccine, dueAt: dueAt)

        await service.schedule(for: reminder)

        let id = service.notificationID(reminderID: reminder.id, offsetDays: 7)
        let request = try XCTUnwrap(center.requests[id])
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.day, 23)
        XCTAssertEqual(trigger.dateComponents.hour, 15)
    }
}
