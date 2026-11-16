//
//  Pet.swift
//  PawLog
//
//  宠物档案模型。
//

import Foundation
import SwiftData

/// 宠物物种
enum PetSpecies: String, Codable, CaseIterable {
    case cat
    case dog
    case other
}

/// 宠物性别
enum PetSex: String, Codable, CaseIterable {
    case male
    case female
    case unknown
}

@Model
final class Pet {
    var id: UUID
    var name: String
    var species: PetSpecies
    var breed: String?
    var birthday: Date?
    var birthEstimated: Bool
    var sex: PetSex
    var neutered: Bool?
    var idealWeightKg: Double?
    var allergies: String?
    var foodBrand: String?
    var chipID: String?
    var avatarData: Data?
    var archived: Bool
    /// 手动排序序号，越小越靠前
    var sortIndex: Int = 0
    var createdAt: Date

    // MARK: - 同步元数据
    // 全部给默认值，旧 store 迁移时无需额外处理；备份 JSON 不含这些字段，
    // 因此不需要升级备份 schemaVersion（缺省即为默认值）。
    /// 本设备最后一次修改时间
    var localUpdatedAt: Date = Date.distantPast
    /// 最后一次修改来源设备
    var deviceID: String = ""
    /// 墓碑：非空表示已删除，等待同步
    var deletedAt: Date?
    /// 乐观并发用的变更标记
    var changeTag: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Record.pet)
    var records: [Record] = []

    @Relationship(deleteRule: .cascade, inverse: \WeightEntry.pet)
    var weightEntries: [WeightEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \Reminder.pet)
    var reminders: [Reminder] = []

    init(
        id: UUID = UUID(),
        name: String,
        species: PetSpecies,
        breed: String? = nil,
        birthday: Date? = nil,
        birthEstimated: Bool = false,
        sex: PetSex = .unknown,
        neutered: Bool? = nil,
        idealWeightKg: Double? = nil,
        allergies: String? = nil,
        foodBrand: String? = nil,
        chipID: String? = nil,
        avatarData: Data? = nil,
        archived: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.breed = breed
        self.birthday = birthday
        self.birthEstimated = birthEstimated
        self.sex = sex
        self.neutered = neutered
        self.idealWeightKg = idealWeightKg
        self.allergies = allergies
        self.foodBrand = foodBrand
        self.chipID = chipID
        self.avatarData = avatarData
        self.archived = archived
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
