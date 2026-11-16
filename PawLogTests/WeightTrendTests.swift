//
//  WeightTrendTests.swift
//  PawLogTests
//
//  验证 5% 阈值边界、连续 3 次同向、数据不足不触发、跨区间不误判、同日去重。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class WeightTrendTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: WeightTrendService!
    private var pet: Pet!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            configurations: config
        )
        context = container.mainContext
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        service = WeightTrendService(calendar: calendar, clock: FixedClock(now))
        pet = Pet(name: "测试宠物", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        service = nil
        pet = nil
        context = nil
        container = nil
        calendar = nil
        now = nil
    }

    // MARK: - 辅助

    @discardableResult
    private func addWeight(_ kg: Double, daysAgo: Int, bcs: Int? = nil, hour: Int = 9) throws -> WeightEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let entry = WeightEntry(pet: pet, weightKg: kg, bcs: bcs, date: date)
        context.insert(entry)
        try context.save()
        return entry
    }

    private var entries: [WeightEntry] {
        Array(pet.weightEntries)
    }

    // MARK: - 阈值边界

    /// 恰好 5% 上升应触发
    func testExactlyFivePercentRiseTriggers() throws {
        try addWeight(10.0, daysAgo: 20)
        try addWeight(10.2, daysAgo: 10)
        try addWeight(10.5, daysAgo: 1)

        guard case .rapidChange(let isRising, let percent)? = service.alert(from: entries) else {
            return XCTFail("恰好 5% 应触发提示")
        }
        XCTAssertTrue(isRising)
        XCTAssertEqual(percent, 0.05, accuracy: 0.0001)
    }

    /// 恰好 5% 下降应触发，且方向为下降
    func testExactlyFivePercentDropTriggers() throws {
        try addWeight(10.0, daysAgo: 20)
        try addWeight(9.8, daysAgo: 10)
        try addWeight(9.5, daysAgo: 1)

        guard case .rapidChange(let isRising, let percent)? = service.alert(from: entries) else {
            return XCTFail("恰好 5% 下降应触发提示")
        }
        XCTAssertFalse(isRising)
        XCTAssertEqual(percent, 0.05, accuracy: 0.0001)
    }

    /// 不足 5% 且非连续同向时不触发
    func testBelowThresholdDoesNotTrigger() throws {
        try addWeight(10.0, daysAgo: 20)
        try addWeight(10.49, daysAgo: 10)
        try addWeight(10.4, daysAgo: 1)

        XCTAssertNil(service.alert(from: entries))
    }

    // MARK: - 连续同向

    /// 最近 3 次连续上升触发（幅度未达 5%）
    func testThreeConsecutiveRisesTrigger() throws {
        try addWeight(4.00, daysAgo: 20)
        try addWeight(4.01, daysAgo: 10)
        try addWeight(4.02, daysAgo: 1)

        XCTAssertEqual(service.alert(from: entries), .consecutive(isRising: true))
    }

    /// 最近 3 次连续下降触发
    func testThreeConsecutiveDropsTrigger() throws {
        try addWeight(4.02, daysAgo: 20)
        try addWeight(4.01, daysAgo: 10)
        try addWeight(4.00, daysAgo: 1)

        XCTAssertEqual(service.alert(from: entries), .consecutive(isRising: false))
    }

    // MARK: - 数据不足

    /// 不足 3 次不触发，即使变化幅度很大
    func testFewerThanThreePointsDoesNotTrigger() throws {
        try addWeight(4.0, daysAgo: 20)
        try addWeight(5.0, daysAgo: 1)

        XCTAssertNil(service.alert(from: entries))
    }

    /// 无数据不触发
    func testNoDataDoesNotTrigger() {
        XCTAssertNil(service.alert(from: []))
        XCTAssertTrue(service.points(for: pet, days: 90).isEmpty)
    }

    // MARK: - 跨区间不误判

    /// 30 天窗口外的旧数据不参与判定；切换图表区间不影响提示结论
    func testAlertIgnoresDataOutsideWindow() throws {
        // 40 天前体重 8.0，若误把旧数据算进来会得到 -50% 的剧烈下降
        try addWeight(8.0, daysAgo: 40)
        try addWeight(4.00, daysAgo: 20)
        try addWeight(4.01, daysAgo: 10)
        try addWeight(4.02, daysAgo: 1)

        XCTAssertEqual(service.points(for: pet, days: 30).count, 3)
        XCTAssertEqual(service.points(for: pet, days: 365).count, 4)
        XCTAssertEqual(service.alert(from: entries), .consecutive(isRising: true))
    }

    /// 30 天内不足 3 次时，即使区间外有更多数据也不触发
    func testWindowWithTwoPointsDoesNotTrigger() throws {
        try addWeight(8.0, daysAgo: 100)
        try addWeight(4.0, daysAgo: 20)
        try addWeight(5.0, daysAgo: 1)

        XCTAssertEqual(service.points(for: pet, days: 365).count, 3)
        XCTAssertNil(service.alert(from: entries))
    }

    // MARK: - 同日去重

    /// 同日多次记录取最后一条
    func testSameDayKeepsLastEntry() throws {
        try addWeight(4.0, daysAgo: 1, hour: 8)
        try addWeight(4.3, daysAgo: 1, hour: 20)

        let points = service.points(for: pet, days: 30)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.weightKg ?? 0, 4.3, accuracy: 0.0001)
    }

    /// BCS 随点位保留，无 BCS 时为 nil
    func testBCSIsCarriedOnPoint() throws {
        try addWeight(4.0, daysAgo: 2, bcs: 6)
        try addWeight(4.1, daysAgo: 1, bcs: nil)

        let points = service.points(for: pet, days: 30)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first?.bcs, 6)
        XCTAssertNil(points.last?.bcs)
    }
}
