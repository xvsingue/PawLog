//
//  BackupTestHarness.swift
//  PawLogTests
//
//  备份测试的共用夹具：内存容器、示例数据、异常 JSON 构造。
//

import Foundation
import SwiftData
import XCTest
@testable import PawLog

@MainActor
final class BackupTestHarness {
    let container: ModelContainer
    let context: ModelContext
    let directory: URL
    let center = FakeNotificationCenter()
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let calendar = Calendar(identifier: .gregorian)

    /// 示例数据的关键字段快照（删除后原对象会失效）
    struct Seed {
        let petID: UUID
        let petName: String
        let recordID: UUID
        let occurredAt: Date
        let payloadJSON: String
        let attachmentID: UUID
        let fileBytes: Data
        let thumbnail: Data
    }

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
            Attachment.self, Entitlement.self, configurations: config
        )
        context = container.mainContext
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PawLogBackupTests-\(UUID().uuidString)", isDirectory: true)
    }

    func makeNotificationService() -> NotificationService {
        NotificationService(center: center, calendar: calendar, clock: FixedClock(now))
    }

    func makeService() -> BackupService {
        BackupService(
            context: context,
            clock: FixedClock(now),
            notificationService: makeNotificationService(),
            attachmentDirectory: directory
        )
    }

    /// 写入 1 只宠物、1 条用药记录、1 条体重、1 条提醒、1 个 PDF 附件
    @discardableResult
    func seed() throws -> Seed {
        let pet = Pet(name: "咪咪", species: .cat, breed: "英短", sortIndex: 0)
        context.insert(pet)

        let payloadJSON = PayloadCoding.encode(
            MedicationPayload(drugName: "阿莫西林", dosage: "5mg", frequency: "每日两次")
        )
        let record = Record(
            pet: pet,
            type: .medication,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: "阿莫西林",
            note: "饭后",
            payloadJSON: payloadJSON
        )
        context.insert(record)

        context.insert(
            WeightEntry(pet: pet, weightKg: 4.5, bcs: 5,
                        date: Date(timeIntervalSince1970: 1_700_100_000), recordID: record.id)
        )
        context.insert(
            Reminder(pet: pet, kind: .medication, sourceRecordID: record.id,
                     dueAt: Date(timeIntervalSince1970: 1_700_200_000))
        )

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data((0..<512).map { UInt8($0 % 251) })
        let fileURL = directory.appendingPathComponent("sample.pdf")
        try bytes.write(to: fileURL)

        let thumbnail = Data([0x01, 0x02, 0x03, 0x04])
        let attachment = Attachment(
            record: record, kind: .pdf, localPath: fileURL.path, thumbnailData: thumbnail
        )
        context.insert(attachment)

        try context.save()

        return Seed(
            petID: pet.id,
            petName: pet.name,
            recordID: record.id,
            occurredAt: record.occurredAt,
            payloadJSON: payloadJSON,
            attachmentID: attachment.id,
            fileBytes: bytes,
            thumbnail: thumbnail
        )
    }

    /// 写入 N 条启用提醒（2 天后到期，每条只产生 1 条有效提前通知）
    func seedReminders(count: Int) throws {
        let pet = Pet(name: "闹钟猫", species: .cat)
        context.insert(pet)
        for index in 0..<count {
            let due = now.addingTimeInterval(2 * 86_400 + Double(index) * 3_600)
            context.insert(Reminder(pet: pet, kind: .custom, dueAt: due))
        }
        try context.save()
    }

    func emptyEverything() throws {
        for record in try context.fetch(FetchDescriptor<Record>()) { context.delete(record) }
        for entry in try context.fetch(FetchDescriptor<WeightEntry>()) { context.delete(entry) }
        for reminder in try context.fetch(FetchDescriptor<Reminder>()) { context.delete(reminder) }
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) { context.delete(attachment) }
        for pet in try context.fetch(FetchDescriptor<Pet>()) { context.delete(pet) }
        try context.save()
    }

    /// 导出后按需改写 JSON 字段，用于构造异常备份
    func mutatedExport(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
        let data = try makeService().exportData()
        var dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        mutate(&dict)
        return try JSONSerialization.data(withJSONObject: dict)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
