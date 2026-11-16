//
//  ReminderFreeLimitTests.swift
//  PawLogTests
//
//  免费提醒上限：仅最近 3 条排通知，其余保留可见，升级后恢复全部排期。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class ReminderFreeLimitTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var center: FakeNotificationCenter!
    private var calendar: Calendar!
    private var now: Date!
    private var pet: Pet!

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
        pet = Pet(name: "咪咪", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        pet = nil
        center = nil
        context = nil
        container = nil
        calendar = nil
        now = nil
    }

    private func notificationService() -> NotificationService {
        NotificationService(center: center, calendar: calendar, clock: FixedClock(now))
    }

    private func reminderService(limit: Int?) -> ReminderService {
        ReminderService(
            context: context,
            notificationService: notificationService(),
            calendar: calendar,
            clock: FixedClock(now),
            reminderLimit: { limit }
        )
    }

    /// 生成 6 条派生提醒，到期日均在 2 天后（仅 1 天前那条提前提醒有效）
    private func makeSixDerivedReminders() async throws {
        let due = calendar.date(byAdding: .day, value: 2, to: now)!
        for index in 0..<6 {
            let record = Record(
                pet: pet,
                type: .vaccine,
                occurredAt: calendar.date(byAdding: .day, value: -index, to: now)!,
                title: "疫苗 \(index)",
                payloadJSON: PayloadCoding.encode(VaccinePayload(vaccineName: "猫三联", nextDate: due))
            )
            context.insert(record)
        }
        try context.save()

        let service = reminderService(limit: 3)
        for record in pet.records {
            await service.deriveReminder(from: record)
        }
    }

    /// 免费用户：6 条派生提醒只排 3 条通知，其余保留
    func testFreeUserOnlySchedulesThreeNotifications() async throws {
        try await makeSixDerivedReminders()

        let reminders = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertEqual(reminders.count, 6, "提醒数据不得删除")
        XCTAssertTrue(reminders.allSatisfy(\.enabled), "不得静默禁用")

        XCTAssertEqual(center.requests.count, 3, "免费用户 pending 应恰好 3 条")

        let service = reminderService(limit: 3)
        let groups = service.fetchReminders(for: pet)
        XCTAssertEqual(groups.upcoming.count + groups.overdue.count, 6, "全部提醒仍应可见")
    }

    /// 升级后：全部 6 条重新排期
    func testUpgradeSchedulesAllSixNotifications() async throws {
        try await makeSixDerivedReminders()
        XCTAssertEqual(center.requests.count, 3)

        await reminderService(limit: nil).reconcileAll()

        XCTAssertEqual(center.requests.count, 6, "升级后 pending 应为 6 条")
        let reminders = try context.fetch(FetchDescriptor<Reminder>())
        XCTAssertEqual(reminders.count, 6)
    }
}
