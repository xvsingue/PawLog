//
//  EntitlementServiceTests.swift
//  PawLogTests
//
//  权益判定与限额：购买、过期、退款、恢复、宠物/提醒上限、历史窗口锁定。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class EntitlementServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var now: Date!
    private var calendar: Calendar!
    private var service: EntitlementService!

    private let monthlyID = StoreKitService.monthlyID
    private let lifetimeID = StoreKitService.lifetimeID

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            configurations: config
        )
        context = container.mainContext
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        service = EntitlementService(context: context, clock: FixedClock(now))
    }

    override func tearDownWithError() throws {
        service = nil
        context = nil
        container = nil
        calendar = nil
        now = nil
    }

    private func date(daysFromNow days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    // MARK: - 购买与回落

    /// 购买订阅后 isPro 为真且限额放开
    func testPurchaseUnlocksProAndLimits() {
        service.apply(PurchaseEvent(
            productID: monthlyID,
            purchasedAt: now,
            expiresAt: date(daysFromNow: 30)
        ))

        XCTAssertTrue(service.isPro)
        XCTAssertEqual(service.petLimit, EntitlementService.proPetLimit)
        XCTAssertNil(service.reminderLimit, "Pro 提醒数不限")
        XCTAssertNil(service.historyWindowDays, "Pro 历史不限")
        XCTAssertTrue(service.canAddPet(currentCount: 19))
    }

    /// 订阅过期后回落免费态
    func testExpiredSubscriptionFallsBackToFree() {
        service.apply(PurchaseEvent(
            productID: monthlyID,
            purchasedAt: date(daysFromNow: -60),
            expiresAt: date(daysFromNow: -1)
        ))

        XCTAssertFalse(service.isPro)
        XCTAssertEqual(service.petLimit, EntitlementService.freePetLimit)
        XCTAssertEqual(service.reminderLimit, EntitlementService.freeReminderLimit)
        XCTAssertEqual(service.historyWindowDays, EntitlementService.freeHistoryDays)
    }

    /// 退款/撤销后回落免费态
    func testRevocationFallsBackToFree() {
        service.apply(PurchaseEvent(
            productID: monthlyID,
            purchasedAt: now,
            expiresAt: date(daysFromNow: 30)
        ))
        XCTAssertTrue(service.isPro)

        service.apply(PurchaseEvent(
            productID: monthlyID,
            purchasedAt: now,
            expiresAt: date(daysFromNow: 30),
            revokedAt: now
        ))

        XCTAssertFalse(service.isPro)
        XCTAssertTrue(service.entitlements.allSatisfy { !$0.isActive })
    }

    /// 恢复购买可还原 Pro
    func testRestoreRebuildsPro() {
        service.apply(events: [
            PurchaseEvent(productID: lifetimeID, purchasedAt: now, expiresAt: nil)
        ])

        XCTAssertTrue(service.isPro)
        XCTAssertEqual(service.entitlements.filter(\.isActive).count, 1)
    }

    /// 同一产品重复购买只保留一条权益
    func testRenewalUpdatesSingleEntitlement() {
        service.apply(PurchaseEvent(productID: monthlyID, purchasedAt: now, expiresAt: date(daysFromNow: 30)))
        service.apply(PurchaseEvent(productID: monthlyID, purchasedAt: now, expiresAt: date(daysFromNow: 60)))

        XCTAssertEqual(service.entitlements.count, 1)
        XCTAssertEqual(service.entitlements.first?.expiresAt, date(daysFromNow: 60))
    }

    // MARK: - 限额

    /// 免费版第 2 只宠物被拦截
    func testPetLimitBlocksSecondPet() {
        XCTAssertTrue(service.canAddPet(currentCount: 0))
        XCTAssertFalse(service.canAddPet(currentCount: 1), "免费版最多 1 只宠物")

        service.apply(PurchaseEvent(productID: lifetimeID, purchasedAt: now, expiresAt: nil))
        XCTAssertTrue(service.canAddPet(currentCount: 1))
        XCTAssertTrue(service.canAddPet(currentCount: 19))
        XCTAssertFalse(service.canAddPet(currentCount: 20))
    }

    /// 免费版第 4 条提醒被拦截
    func testReminderLimitBlocksFourthReminder() {
        XCTAssertTrue(service.canEnableReminder(currentEnabled: 2))
        XCTAssertFalse(service.canEnableReminder(currentEnabled: 3), "免费版最多 3 条提醒")

        service.apply(PurchaseEvent(productID: lifetimeID, purchasedAt: now, expiresAt: nil))
        XCTAssertTrue(service.canEnableReminder(currentEnabled: 100), "Pro 提醒不限")
    }

    /// 免费用户 90 天外记录为锁定态
    func testHistoryWindowLocksOldRecords() {
        XCTAssertFalse(service.isLocked(date: date(daysFromNow: -89)))
        XCTAssertTrue(service.isLocked(date: date(daysFromNow: -91)), "免费版 90 天外应锁定")

        service.apply(PurchaseEvent(productID: monthlyID, purchasedAt: now, expiresAt: date(daysFromNow: 30)))
        XCTAssertFalse(service.isLocked(date: date(daysFromNow: -365)))
    }

    /// 数据不因锁定被删除：仅判定，不触碰记录
    func testLockingDoesNotDeleteRecords() throws {
        let pet = Pet(name: "咪咪", species: .cat)
        context.insert(pet)
        let old = Record(
            pet: pet,
            type: .vaccine,
            occurredAt: date(daysFromNow: -120),
            title: "旧疫苗"
        )
        context.insert(old)
        try context.save()

        XCTAssertTrue(service.isLocked(date: old.occurredAt))
        let fetched = try context.fetch(FetchDescriptor<Record>())
        XCTAssertEqual(fetched.count, 1, "锁定态不得删除数据")
    }
}
