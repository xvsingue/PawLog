//
//  TimelineSearchTests.swift
//  PawLogTests
//
//  时间线搜索：多字段命中、大小写无关、中文空格容错、与类型筛选叠加、空态与清空恢复。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class TimelineSearchTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var pet: Pet!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self, configurations: config
        )
        context = container.mainContext
        pet = Pet(name: "咪咪", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        pet = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func add(
        _ type: RecordType,
        title: String,
        note: String? = nil,
        payloadJSON: String = ""
    ) -> Record {
        let record = Record(
            pet: pet,
            type: type,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: title,
            note: note,
            payloadJSON: payloadJSON
        )
        context.insert(record)
        return record
    }

    // MARK: - 多字段命中

    func testMatchesTitle() {
        let record = add(.visit, title: "年度体检")
        XCTAssertTrue(TimelineSearch.matches(record, query: "体检"))
    }

    func testMatchesNote() {
        let record = add(.daily, title: "日常", note: "今天精神不错")
        XCTAssertTrue(TimelineSearch.matches(record, query: "精神"))
    }

    func testMatchesTypeName() {
        let record = add(.vaccine, title: "猫三联")
        let typeName = RecordType.vaccine.localizedTitle
        XCTAssertTrue(TimelineSearch.matches(record, query: typeName))
    }

    func testMatchesDrugName() {
        let payload = PayloadCoding.encode(
            MedicationPayload(drugName: "阿莫西林", dosage: "5mg", frequency: "每日两次")
        )
        let record = add(.medication, title: "用药", payloadJSON: payload)
        XCTAssertTrue(TimelineSearch.matches(record, query: "阿莫西林"))
    }

    func testMatchesHospitalNameInVisit() {
        let payload = PayloadCoding.encode(VisitPayload(hospital: "安心宠物医院"))
        let record = add(.visit, title: "就诊", payloadJSON: payload)
        XCTAssertTrue(TimelineSearch.matches(record, query: "宠物医院"))
    }

    func testMatchesHospitalNameInVaccine() {
        let payload = PayloadCoding.encode(VaccinePayload(vaccineName: "狂犬", hospital: "城东动物诊所"))
        let record = add(.vaccine, title: "狂犬", payloadJSON: payload)
        XCTAssertTrue(TimelineSearch.matches(record, query: "城东"))
    }

    // MARK: - 大小写与空格

    func testCaseInsensitive() {
        let record = add(.medication, title: "Amoxicillin")
        XCTAssertTrue(TimelineSearch.matches(record, query: "amoxicillin"))
        XCTAssertTrue(TimelineSearch.matches(record, query: "AMOXICILLIN"))
    }

    func testIgnoresChineseFullWidthSpace() {
        let record = add(.vaccine, title: "猫三联")
        XCTAssertTrue(TimelineSearch.matches(record, query: "猫\u{3000}三联"))
        XCTAssertTrue(TimelineSearch.matches(record, query: "猫 三联"))
    }

    func testIgnoresLeadingAndTrailingSpaces() {
        let record = add(.visit, title: "年度体检")
        XCTAssertTrue(TimelineSearch.matches(record, query: "  体检  "))
    }

    // MARK: - 叠加与空态

    func testEmptyQueryKeepsAllRecords() {
        let a = add(.visit, title: "就诊")
        let b = add(.weight, title: "体重")
        let result = TimelineSearch.filter([a, b], query: "")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(TimelineSearch.filter([a, b], query: "   ").count, 2)
    }

    func testNoMatchReturnsEmpty() {
        let record = add(.visit, title: "就诊")
        XCTAssertTrue(TimelineSearch.filter([record], query: "不存在的关键词").isEmpty)
    }

    func testSearchCombinedWithTypeFilter() {
        let visit = add(.visit, title: "安心医院复查")
        let vaccine = add(.vaccine, title: "安心医院接种")

        let byType = [visit, vaccine].filter { $0.type == .visit }
        let result = TimelineSearch.filter(byType, query: "安心医院")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .visit)
    }

    func testClearingQueryRestoresFullList() {
        let a = add(.visit, title: "就诊")
        let b = add(.vaccine, title: "疫苗")

        XCTAssertEqual(TimelineSearch.filter([a, b], query: "疫").count, 1)
        XCTAssertEqual(TimelineSearch.filter([a, b], query: "").count, 2)
    }
}
