//
//  QuickRecordTapCountUITests.swift
//  PawLogUITests
//
//  实测：从首页加号到保存一条记录的点击次数；并验证默认值可直接保存。
//

import XCTest

final class QuickRecordTapCountUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDewormingSavesInThreeTaps() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        // 准备数据：建档（不計入记录保存的点击数）
        let addPet = app.buttons["home.addPet"]
        XCTAssertTrue(addPet.waitForExistence(timeout: 20), "首页空状态未出现")
        addPet.tap()

        let addFirst = app.buttons["pet.addFirst"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 10), "宠物列表空状态未出现")
        addFirst.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "建档表单未出现")
        nameField.tap()
        nameField.typeText("咪咪")
        app.buttons["pet.save"].tap()

        let done = app.buttons["pet.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "宠物列表未回到可关闭状态")
        done.tap()

        // 正式计数
        var taps = 0

        let addRecord = app.buttons["home.addRecord"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 10), "首页加号未出现")
        addRecord.tap()
        taps += 1

        let deworming = app.buttons["record.type.deworming"]
        XCTAssertTrue(deworming.waitForExistence(timeout: 10), "类型选择未出现")
        deworming.tap()
        taps += 1

        let save = app.buttons["record.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "保存按钮未出现")
        XCTAssertTrue(save.isEnabled, "驱虫默认值下保存按钮应可用")
        save.tap()
        taps += 1

        // 保存成功：回到时间线并出现该记录标题（驱虫范围默认"体内外"）
        XCTAssertTrue(
            app.staticTexts["体内外"].waitForExistence(timeout: 10),
            "保存后时间线未出现新记录"
        )
        XCTAssertEqual(taps, 3, "保存一条驱虫记录应为 3 次点击")
    }
}
