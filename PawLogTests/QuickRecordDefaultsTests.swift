//
//  QuickRecordDefaultsTests.swift
//  PawLogTests
//
//  验证快速记录表单的默认值：日期今天、可直接保存、医院/药品沿用上次。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class QuickRecordDefaultsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: RecordService!
    private var pet: Pet!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        service = RecordService(context: context)
        pet = Pet(name: "测试宠物", species: .cat)
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        service = nil
        pet = nil
        context = nil
        container = nil
    }

    /// 驱虫 / 症状 / 日常：默认值即可保存，日期默认今天
    func testDefaultDraftIsSavableWithoutInput() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for type in [RecordType.deworming, .symptom, .daily] {
            let viewModel = QuickRecordViewModel(pet: pet, service: service, type: type)
            XCTAssertTrue(viewModel.isValid, "\(type) 默认值下应可直接保存")
            XCTAssertEqual(
                calendar.startOfDay(for: viewModel.draft.occurredAt),
                today,
                "\(type) 日期应默认今天"
            )
        }

        let viewModel = QuickRecordViewModel(pet: pet, service: service, type: .deworming)
        XCTAssertNoThrow(try viewModel.save())

        XCTAssertEqual(pet.records.count, 1)
        let record = try XCTUnwrap(pet.records.first)
        XCTAssertEqual(record.type, .deworming)
        XCTAssertNotNil(record.payload(DewormingPayload.self))
    }

    /// 需要必填输入的类型，空表单不可保存
    func testRequiredTypesNeedInput() {
        for type in [RecordType.vaccine, .visit, .weight] {
            let viewModel = QuickRecordViewModel(pet: pet, service: service, type: type)
            XCTAssertFalse(viewModel.isValid, "\(type) 缺少必填项时不应可保存")
        }
    }

    /// 医院与药品沿用上次使用值
    func testHospitalAndDrugDefaultToLastUsed() throws {
        try service.create(
            pet: pet,
            type: .visit,
            occurredAt: Date(),
            title: "宠物医院",
            note: nil,
            payloadJSON: PayloadCoding.encode(VisitPayload(hospital: "康宁宠物医院"))
        )
        try service.create(
            pet: pet,
            type: .medication,
            occurredAt: Date(),
            title: "阿莫西林",
            note: nil,
            payloadJSON: PayloadCoding.encode(MedicationPayload(drugName: "阿莫西林", dosage: "50mg", frequency: "每日两次"))
        )

        let visitForm = QuickRecordViewModel(pet: pet, service: service, type: .visit)
        XCTAssertEqual(visitForm.draft.hospital, "康宁宠物医院")

        let medicationForm = QuickRecordViewModel(pet: pet, service: service, type: .medication)
        XCTAssertEqual(medicationForm.draft.drugName, "阿莫西林")
    }
}
