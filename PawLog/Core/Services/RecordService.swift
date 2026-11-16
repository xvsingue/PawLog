//
//  RecordService.swift
//  PawLog
//
//  记录读写：日期校验、增删改、体重双写、上次医院/药品取值。
//

import Foundation
import SwiftData

/// 体重输入
struct WeightInput {
    var kg: Double
    var bcs: Int?
}

/// 记录服务错误
enum RecordServiceError: LocalizedError, Equatable {
    /// 记录日期晚于今天
    case dateInFuture
    /// 记录日期早于 5 年前
    case dateTooOld

    var errorDescription: String? {
        switch self {
        case .dateInFuture: return String(localized: "record.error.dateInFuture")
        case .dateTooOld: return String(localized: "record.error.dateTooOld")
        }
    }
}

/// 记录数据服务
@MainActor
final class RecordService {
    /// 允许回溯的年数
    static let maxPastYears = 5

    private let context: ModelContext
    private let calendar = Calendar.current
    private let reminderService: ReminderService?
    private let changes: ChangeLogService
    private let clock: Clock

    init(
        context: ModelContext,
        reminderService: ReminderService? = nil,
        deviceID: String = DeviceIdentity.current(),
        clock: Clock = SystemClock()
    ) {
        self.context = context
        self.reminderService = reminderService
        self.clock = clock
        self.changes = ChangeLogService(context: context, deviceID: deviceID, clock: clock)
    }

    // MARK: - 校验

    /// 校验记录日期：不得晚于今天，最早不超过 5 年前
    func validate(occurredAt: Date, now: Date = Date()) throws {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        if occurredAt >= endOfToday {
            throw RecordServiceError.dateInFuture
        }
        if let earliest = calendar.date(byAdding: .year, value: -Self.maxPastYears, to: startOfToday),
           occurredAt < earliest {
            throw RecordServiceError.dateTooOld
        }
    }

    // MARK: - 写

    /// 新建记录。体重类型同时写入一条 WeightEntry。
    @discardableResult
    func create(
        pet: Pet,
        type: RecordType,
        occurredAt: Date,
        title: String,
        note: String?,
        payloadJSON: String,
        weight: WeightInput? = nil,
        now: Date = Date()
    ) throws -> Record {
        try validate(occurredAt: occurredAt, now: now)

        let record = Record(
            pet: pet,
            type: type,
            occurredAt: occurredAt,
            title: title,
            note: note,
            payloadJSON: payloadJSON
        )
        context.insert(record)
        syncWeight(for: record, input: weight)
        try changes.record(record, kind: .record, operation: .create)
        try context.save()
        return record
    }

    /// 更新记录。体重类型同步更新对应 WeightEntry；改为非体重类型时删除旧 WeightEntry。
    /// 下次日期变化时同步重排派生提醒。
    func update(
        _ record: Record,
        occurredAt: Date,
        title: String,
        note: String?,
        payloadJSON: String,
        weight: WeightInput? = nil,
        now: Date = Date()
    ) throws {
        try validate(occurredAt: occurredAt, now: now)

        let previousNextDate = ReminderService.nextDateAndKind(for: record)?.1

        record.occurredAt = occurredAt
        record.title = title
        record.note = note
        record.payloadJSON = payloadJSON
        record.updatedAt = now
        syncWeight(for: record, input: weight)
        try changes.record(record, kind: .record, operation: .update, at: now)
        try context.save()

        syncReminderAfterUpdate(for: record, previousNextDate: previousNextDate)
    }

    /// 下次日期变化时重排提醒；被清空则删除派生提醒
    private func syncReminderAfterUpdate(for record: Record, previousNextDate: Date?) {
        guard let reminderService else { return }
        let currentNextDate = ReminderService.nextDateAndKind(for: record)?.1
        guard currentNextDate != previousNextDate else { return }

        if currentNextDate == nil {
            reminderService.deleteDerivedReminders(for: record)
            return
        }
        guard let reminder = try? reminderService.upsertDerivedReminder(for: record) else { return }
        Task { await reminderService.reschedule(reminder) }
    }

    /// 删除记录：写墓碑（供其它设备同步感知），同时物理清理关联的 WeightEntry
    /// 与派生提醒并撤销通知。
    func delete(_ record: Record) throws {
        reminderService?.deleteDerivedReminders(for: record)
        for entry in record.pet?.weightEntries ?? [] where entry.recordID == record.id {
            context.delete(entry)
        }
        let now = clock.now
        try changes.record(record, kind: .record, operation: .delete, at: now)
        record.deletedAt = now
        try context.save()
    }

    // MARK: - 体重双写

    /// 保持 Record 与 WeightEntry 一致：体重类型写入/更新，其他类型清理
    private func syncWeight(for record: Record, input: WeightInput?) {
        let existing = record.pet?.weightEntries.first {
            $0.recordID == record.id && $0.deletedAt == nil
        }

        guard record.type == .weight, let input else {
            if let existing {
                context.delete(existing)
            }
            return
        }

        if let existing {
            existing.weightKg = input.kg
            existing.bcs = input.bcs
            existing.date = record.occurredAt
        } else {
            let entry = WeightEntry(
                pet: record.pet,
                weightKg: input.kg,
                bcs: input.bcs,
                date: record.occurredAt,
                recordID: record.id
            )
            context.insert(entry)
        }
    }

    // MARK: - 智能默认

    /// 最近一次使用的医院（疫苗或就诊）
    func lastHospital(for pet: Pet) -> String? {
        for record in pet.records.active.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            switch record.type {
            case .vaccine:
                if let hospital = record.payload(VaccinePayload.self)?.hospital, !hospital.isEmpty {
                    return hospital
                }
            case .visit:
                if let hospital = record.payload(VisitPayload.self)?.hospital, !hospital.isEmpty {
                    return hospital
                }
            default:
                break
            }
        }
        return nil
    }

    /// 最近一次使用的药品（用药或驱虫）
    func lastDrugName(for pet: Pet) -> String? {
        for record in pet.records.active.sorted(by: { $0.occurredAt > $1.occurredAt }) {
            switch record.type {
            case .medication:
                if let name = record.payload(MedicationPayload.self)?.drugName, !name.isEmpty {
                    return name
                }
            case .deworming:
                if let name = record.payload(DewormingPayload.self)?.drugName, !name.isEmpty {
                    return name
                }
            default:
                break
            }
        }
        return nil
    }
}
