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
    var createdAt: Date

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
        self.createdAt = createdAt
    }
}
