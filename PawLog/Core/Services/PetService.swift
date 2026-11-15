//
//  PetService.swift
//  PawLog
//
//  宠物数据服务：封装 ModelContext 的增删改查。View 不直接操作数据。
//

import Foundation
import SwiftData

/// 宠物数据服务
@MainActor
final class PetService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 获取未归档宠物，按手动排序、再按创建时间升序
    func fetchPets() throws -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate { !$0.archived },
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
        }
        try context.save()
    }

    /// 保存对现有宠物的修改
    func saveChanges() throws {
        try context.save()
    }

    /// 统计宠物的记录条数（仅 Record，用于删除确认提示）
    func countRecords(for pet: Pet) -> Int {
        pet.records.count
    }

    /// 删除宠物（级联删除全部记录及其附件、体重、提醒），返回被删除的 Record 条数
    @discardableResult
    func deletePet(_ pet: Pet) throws -> Int {
        let count = countRecords(for: pet)
        context.delete(pet)
        try context.save()
        return count
    }
}
