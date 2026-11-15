//
//  RecordServiceTests.swift
//  PawLogTests
//
//  验证记录日期校验、体重双写一致性、删除不残留 WeightEntry、旧载荷兼容。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class RecordServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: RecordService!
    private var pet: Pet!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
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

    // MARK: - 体重双写

    /// 新建体重记录时，必须同时写入一条 WeightEntry，且 recordID 关联一致
    func testCreateWeightRecordWritesWeightEntry() throws {
        let occurredAt = Date()
        let record = try service.create(
            pet: pet,
            type: .weight,
            occurredAt: occurredAt,
            title: "4.2 kg",
            note: nil,
            payloadJSON: PayloadCoding.encode(WeightPayload(weightKg: 4.2, unit: "kg", bcs: 5)),
            weight: WeightInput(kg: 4.2, bcs: 5)
        )

        XCTAssertEqual(pet.records.count, 1)
        XCTAssertEqual(pet.weightEntries.count, 1)

        let entry = try XCTUnwrap(pet.weightEntries.first)
        XCTAssertEqual(entry.recordID, record.id)
        XCTAssertEqual(entry.weightKg, 4.2, accuracy: 0.0001)
        XCTAssertEqual(entry.bcs, 5)
        XCTAssertEqual(entry.date, occurredAt)
        XCTAssertEqual(entry.pet?.id, pet.id)

        // 两条表的数据一致
        let payload = try XCTUnwrap(record.payload(WeightPayload.self))
        XCTAssertEqual(payload.weightKg, entry.weightKg, accuracy: 0.0001)
        XCTAssertEqual(payload.bcs, entry.bcs)
    }

    /// 更新体重记录时，WeightEntry 同步更新，且仍只有一条
    func testUpdateWeightRecordSyncsEntry() throws {
        let record = try service.create(
            pet: pet,
            type: .weight,
            occurredAt: Date(),
            title: "4.2 kg",
            note: nil,
            payloadJSON: PayloadCoding.encode(WeightPayload(weightKg: 4.2)),
            weight: WeightInput(kg: 4.2, bcs: nil)
        )

        try service.update(
            record,
            occurredAt: record.occurredAt,
            title: "4.6 kg",
            note: nil,
            payloadJSON: PayloadCoding.encode(WeightPayload(weightKg: 4.6, bcs: 6)),
            weight: WeightInput(kg: 4.6, bcs: 6)
        )

        XCTAssertEqual(pet.weightEntries.count, 1)
        let entry = try XCTUnwrap(pet.weightEntries.first)
        XCTAssertEqual(entry.weightKg, 4.6, accuracy: 0.0001)
        XCTAssertEqual(entry.bcs, 6)
        XCTAssertEqual(entry.recordID, record.id)
    }

    /// 删除体重记录后，不得残留 WeightEntry
    func testDeleteWeightRecordRemovesEntry() throws {
        let record = try service.create(
            pet: pet,
            type: .weight,
            occurredAt: Date(),
            title: "4.2 kg",
            note: nil,
            payloadJSON: PayloadCoding.encode(WeightPayload(weightKg: 4.2)),
            weight: WeightInput(kg: 4.2, bcs: nil)
        )
        XCTAssertEqual(pet.weightEntries.count, 1)

        try service.delete(record)

        XCTAssertEqual(pet.records.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).count, 0)
    }

    /// 非体重记录不写入 WeightEntry
    func testNonWeightRecordDoesNotWriteWeightEntry() throws {
        try service.create(
            pet: pet,
            type: .daily,
            occurredAt: Date(),
            title: "日常",
            note: nil,
            payloadJSON: PayloadCoding.encode(DailyPayload(foodAmount: "50 g"))
        )

        XCTAssertEqual(pet.records.count, 1)
        XCTAssertEqual(pet.weightEntries.count, 0)
    }

    // MARK: - 日期校验

    func testFutureDateIsRejected() throws {
        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        XCTAssertThrowsError(
            try service.create(
                pet: pet,
                type: .daily,
                occurredAt: future,
                title: "日常",
                note: nil,
                payloadJSON: "{}"
            )
        ) { error in
            XCTAssertEqual(error as? RecordServiceError, .dateInFuture)
        }
        XCTAssertEqual(pet.records.count, 0)
    }

    func testDateOlderThanFiveYearsIsRejected() throws {
        let tooOld = Calendar.current.date(byAdding: .year, value: -6, to: Date()) ?? Date()
        XCTAssertThrowsError(
            try service.create(
                pet: pet,
                type: .daily,
                occurredAt: tooOld,
                title: "日常",
                note: nil,
                payloadJSON: "{}"
            )
        ) { error in
            XCTAssertEqual(error as? RecordServiceError, .dateTooOld)
        }
        XCTAssertEqual(pet.records.count, 0)
    }

    // MARK: - 旧数据兼容

    /// 缺字段的旧载荷解码时不崩溃，回退默认值
    func testLegacyPayloadDecodesWithDefaults() {
        let record = Record(type: .vaccine, occurredAt: Date(), title: "旧数据", payloadJSON: "{}")

        let vaccine = record.payload(VaccinePayload.self)
        XCTAssertEqual(vaccine?.vaccineName, "")
        XCTAssertNil(vaccine?.hospital)

        let deworming = record.payload(DewormingPayload.self)
        XCTAssertEqual(deworming?.scope, .both)

        let symptom = record.payload(SymptomPayload.self)
        XCTAssertEqual(symptom?.severity, 1)

        let weight = record.payload(WeightPayload.self)
        XCTAssertEqual(weight?.weightKg ?? -1, 0, accuracy: 0.0001)
    }
}
