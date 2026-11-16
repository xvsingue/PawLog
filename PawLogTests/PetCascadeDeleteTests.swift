//
//  PetCascadeDeleteTests.swift
//  PawLogTests
//
//  验证删除宠物时级联删除其全部 Record / WeightEntry / Reminder / Attachment。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class PetCascadeDeleteTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    /// 删除宠物后，其 Record / WeightEntry / Reminder / Attachment 应全部级联删除
    func testDeletePetCascadesAllRelations() throws {
        let pet = Pet(name: "测试宠物", species: .cat)
        context.insert(pet)

        let record = Record(type: .vaccine, occurredAt: Date(), title: "疫苗")
        record.pet = pet
        context.insert(record)

        let weight = WeightEntry(weightKg: 4.5)
        weight.pet = pet
        context.insert(weight)

        let reminder = Reminder(kind: .vaccine, dueAt: Date())
        reminder.pet = pet
        context.insert(reminder)

        let attachment = Attachment(kind: .image, localPath: "/tmp/test.jpg")
        attachment.record = record
        context.insert(attachment)

        try context.save()

        // 前置断言：关联数据已落库
        XCTAssertEqual(try count(Pet.self), 1)
        XCTAssertEqual(try count(Record.self), 1)
        XCTAssertEqual(try count(WeightEntry.self), 1)
        XCTAssertEqual(try count(Reminder.self), 1)
        XCTAssertEqual(try count(Attachment.self), 1)

        // 删除宠物
        context.delete(pet)
        try context.save()

        // 级联断言：全部清零
        XCTAssertEqual(try count(Pet.self), 0)
        XCTAssertEqual(try count(Record.self), 0)
        XCTAssertEqual(try count(WeightEntry.self), 0)
        XCTAssertEqual(try count(Reminder.self), 0)
        XCTAssertEqual(try count(Attachment.self), 0)
    }

    /// 删除单条记录时，其附件应级联删除，但宠物不受影响
    func testDeleteRecordCascadesAttachmentsOnly() throws {
        let pet = Pet(name: "测试宠物", species: .dog)
        context.insert(pet)

        let record = Record(type: .weight, occurredAt: Date(), title: "体重")
        record.pet = pet
        context.insert(record)

        let attachment = Attachment(kind: .pdf, localPath: "/tmp/report.pdf")
        attachment.record = record
        context.insert(attachment)

        try context.save()

        context.delete(record)
        try context.save()

        XCTAssertEqual(try count(Pet.self), 1)
        XCTAssertEqual(try count(Record.self), 0)
        XCTAssertEqual(try count(Attachment.self), 0)
    }

    // MARK: - Helpers

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetch(FetchDescriptor<T>()).count
    }
}
