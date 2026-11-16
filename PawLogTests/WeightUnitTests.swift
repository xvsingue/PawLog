//
//  WeightUnitTests.swift
//  PawLogTests
//
//  体重单位换算、格式化与理想体重目标带边界。
//

import XCTest
@testable import PawLog

final class WeightUnitTests: XCTestCase {
    /// 0.2–120kg 区间边界
    func testAllowedRangeBoundaries() {
        XCTAssertFalse(WeightFormatter.isWithinRange(0.1), "0.1kg 应视为超界")
        XCTAssertTrue(WeightFormatter.isWithinRange(0.2), "0.2kg 是下边界")
        XCTAssertTrue(WeightFormatter.isWithinRange(120), "120kg 是上边界")
        XCTAssertFalse(WeightFormatter.isWithinRange(120.1), "120.1kg 应视为超界")
        XCTAssertFalse(WeightFormatter.isWithinRange(0))
        XCTAssertFalse(WeightFormatter.isWithinRange(-1))
    }

    /// kg ⇄ lb 换算可往返
    func testConversionRoundTrip() {
        let pounds = WeightFormatter.value(1, in: .lb)
        XCTAssertEqual(pounds, 2.2046, accuracy: 0.001)
        XCTAssertEqual(WeightFormatter.kilograms(pounds, in: .lb), 1, accuracy: 0.0001)
        XCTAssertEqual(WeightFormatter.value(10, in: .kg), 10, accuracy: 0.0001)
    }

    /// 格式化跟随单位
    func testFormattingFollowsUnit() {
        let kg = WeightFormatter.string(10, unit: .kg)
        let lb = WeightFormatter.string(10, unit: .lb)
        XCTAssertTrue(kg.contains("10"), "kg 文案应含数值：\(kg)")
        XCTAssertTrue(lb.contains("22"), "lb 文案应为换算值：\(lb)")
        XCTAssertTrue(lb.lowercased().contains("lb"), "lb 文案应带单位：\(lb)")
    }

    /// 双单位提示同时包含两种单位
    func testDualStringContainsBothUnits() {
        let text = WeightFormatter.dualString(4.2)
        XCTAssertTrue(text.lowercased().contains("kg"))
        XCTAssertTrue(text.lowercased().contains("lb"))
    }

    /// 理想体重 ±10% 目标带
    func testIdealWeightBandKg() {
        let band = IdealWeightBand.bounds(idealKilograms: 4.0, unit: .kg)
        XCTAssertEqual(band.lowerBound, 3.6, accuracy: 0.0001)
        XCTAssertEqual(band.upperBound, 4.4, accuracy: 0.0001)
    }

    /// 目标带随单位换算
    func testIdealWeightBandPounds() {
        let band = IdealWeightBand.bounds(idealKilograms: 4.0, unit: .lb)
        XCTAssertEqual(band.lowerBound, 3.6 * 2.2046226218, accuracy: 0.01)
        XCTAssertEqual(band.upperBound, 4.4 * 2.2046226218, accuracy: 0.01)
    }
}
