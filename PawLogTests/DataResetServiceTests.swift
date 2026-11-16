//
//  DataResetServiceTests.swift
//  PawLogTests
//
//  「清空全部数据」：逐对象删除，五个业务模型清零，Entitlement 保留。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class DataResetServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let center = FakeNotificationCenter()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, configurations: config
        )
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        try super.tearDownWithError()
    }

    private func makeService() -> DataResetService {
        DataResetService(context: context, notificationService: NotificationService(center: center))
    }

    private func seedTwoPets() throws {
        for index in 0..<2 {
            let pet = Pet(name: "宠物\(index)", species: .cat)
            context.insert(pet)

            let record = Record(
                pet: pet,
                type: .weight,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                title: "体重",
                payloadJSON: ""
            )
            context.insert(record)

            context.insert(
                WeightEntry(pet: pet, weightKg: 4.0 + Double(index),
                            date: Date(timeIntervalSince1970: 1_700_000_000), recordID: record.id)
            )
            context.insert(Reminder(pet: pet, kind: .custom, dueAt: Date(timeIntervalSince1970: 1_800_000_000)))
            context.insert(
                Attachment(record: record, kind: .pdf, localPath: "/tmp/\(index).pdf", thumbnailData: nil)
            )
        }
        context.insert(
            Entitlement(
                productID: "com.Lennox.PawLog.pro.lifetime",
                kind: .lifetime,
                purchasedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        try context.save()
    }

    func testClearAllDataEmptiesBusinessModelsAndKeepsEntitlement() async throws {
        try seedTwoPets()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entitlement>()), 1)

        try await makeService().clearAllData()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Record>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeightEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Reminder>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Attachment>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entitlement>()), 1, "购买状态不应被清空")
    }

    func testClearAllDataCancelsPendingNotifications() async throws {
        try seedTwoPets()
        let service = makeService()
        let reminders = try context.fetch(FetchDescriptor<Reminder>())
        let scheduler = ReminderService(context: context, notificationService: NotificationService(center: center))
        await scheduler.reconcileAll()
        XCTAssertFalse(reminders.isEmpty)

        try await service.clearAllData()

        let pending = await center.getPendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty)
    }

    func testClearAllDataOnEmptyStoreDoesNotThrow() async throws {
        try await makeService().clearAllData()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>()), 0)
    }
}
