//
//  PawLogConfigTests.swift
//  PawLogTests
//
//  验证 PawLogConfig.isProEnabled = false（开源版）时的行为：
//  isPro 恒为 true、所有限额放开、canAddPet 不拦截、90 天外记录不锁定。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class PawLogConfigTests: XCTestCase {

    /// 关闭开关时，EntitlementService 所有用户视作 Pro
    func testConfigDisabledMakesEveryonePro() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self, configurations: config
        )

        // 用默认 proEnabled（= PawLogConfig.isProEnabled = false）
        let service = EntitlementService(context: container.mainContext)

        // 即使没买过任何东西，isPro 也为 true
        XCTAssertTrue(service.isPro)

        // petLimit = 20：能创建到第 20 只，第 21 只被拦截（是合理的边界行为）
        XCTAssertEqual(service.petLimit, EntitlementService.proPetLimit)
        XCTAssertTrue(service.canAddPet(currentCount: 0))
        XCTAssertTrue(service.canAddPet(currentCount: 19))
        XCTAssertFalse(service.canAddPet(currentCount: 20))

        // reminderLimit 放开（nil = 无限）
        XCTAssertNil(service.reminderLimit)
        XCTAssertTrue(service.canEnableReminder(currentEnabled: 100))

        // historyWindowDays 放开（nil = 无限）→ 90 天外记录不锁定
        XCTAssertNil(service.historyWindowDays)
        let farPast = Calendar.current.date(byAdding: .day, value: -120, to: Date())!
        XCTAssertFalse(service.isLocked(date: farPast))
    }

    /// 开关显式打开时（上架版），免费限额恢复生效
    func testConfigEnabledReinstatesFreeLimits() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self, configurations: config
        )
        let service = EntitlementService(context: container.mainContext, proEnabled: true)

        // 未购买权益时 isPro = false
        XCTAssertFalse(service.isPro)
        XCTAssertEqual(service.petLimit, EntitlementService.freePetLimit)
        XCTAssertNotNil(service.reminderLimit)
        XCTAssertNotNil(service.historyWindowDays)

        // 90 天外应锁定
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -91, to: now)!
        XCTAssertTrue(service.isLocked(date: cutoff, now: now))
    }
}
