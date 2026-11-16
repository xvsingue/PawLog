//
//  PetService.swift
//  PawLog
//
//  宠物数据服务：封装 ModelContext 的增删改查。View 不直接操作数据。
//  每次写操作都会记录一条 ChangeLog；删除采用墓碑（deletedAt），不做物理删除。
//

import Foundation
import SwiftData

/// 宠物数据服务
@MainActor
final class PetService {
    private let context: ModelContext
    private let changes: ChangeLogService
    private let clock: Clock

    init(
        context: ModelContext,
        deviceID: String = DeviceIdentity.current(),
        clock: Clock = SystemClock()
    ) {
        self.context = context
        self.clock = clock
        self.changes = ChangeLogService(context: context, deviceID: deviceID, clock: clock)
    }

    /// 获取未归档且未删除的宠物，按手动排序、再按创建时间升序
    func fetchPets() throws -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate { !$0.archived && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.sortIndex, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor)
    }

    /// 新建宠物，排序序号取当前最大值 + 1
    func createPet(_ pet: Pet) throws {
        let existing = (try? fetchPets()) ?? []
        pet.sortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        context.insert(pet)
        try changes.record(pet, kind: .pet, operation: .create)
        try context.save()
    }

    /// 重排宠物顺序，在一次 save 内批量重写全部 sortIndex
    func movePets(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let ordered = try fetchPets()

        let removed = Set(source)
        let moving = source.sorted().compactMap { ordered.indices.contains($0) ? ordered[$0] : nil }
        var rest = ordered.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))

        for (index, pet) in rest.enumerated() {
            pet.sortIndex = index
            try changes.record(pet, kind: .pet, operation: .update)
        }
        try context.save()
    }

    /// 保存对现有宠物的修改
    func saveChanges(for pet: Pet) throws {
        try changes.record(pet, kind: .pet, operation: .update)
        try context.save()
    }

    /// 统计宠物的有效记录条数（仅 Record，用于删除确认提示）
    func countRecords(for pet: Pet) -> Int {
        pet.records.filter { $0.deletedAt == nil }.count
    }

    /// 删除宠物：写墓碑并同步给子实体，返回被标记删除的 Record 条数。
    /// 不物理删除，否则其它设备无法感知删除，会出现"删了又回来"。
    @discardableResult
    func deletePet(_ pet: Pet) throws -> Int {
        let now = clock.now
        let recordCount = countRecords(for: pet)

        try changes.record(pet, kind: .pet, operation: .delete, at: now)
        pet.deletedAt = now

        for record in pet.records where record.deletedAt == nil {
            try changes.record(record, kind: .record, operation: .delete, at: now)
            record.deletedAt = now
        }
        for entry in pet.weightEntries where entry.deletedAt == nil {
            try changes.record(entry, kind: .weightEntry, operation: .delete, at: now)
            entry.deletedAt = now
        }
        for reminder in pet.reminders where reminder.deletedAt == nil {
            try changes.record(reminder, kind: .reminder, operation: .delete, at: now)
            reminder.deletedAt = now
        }

        try context.save()
        return recordCount
    }
}
