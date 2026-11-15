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

    /// 获取未归档宠物，按创建时间升序
    func fetchPets() throws -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate { !$0.archived },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// 新建宠物
    func createPet(_ pet: Pet) throws {
        context.insert(pet)
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
