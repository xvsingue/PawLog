//
//  PetEditViewModel.swift
//  PawLog
//

import Foundation
import Combine

@MainActor
final class PetEditViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var species: PetSpecies = .cat
    @Published var breed: String = ""
    @Published var hasBirthday: Bool = false
    @Published var birthday: Date = Date()
    @Published var birthEstimated: Bool = false
    @Published var sex: PetSex = .unknown
    @Published var hasNeutered: Bool = false
    @Published var neutered: Bool = false
    @Published var idealWeightText: String = ""
    @Published var allergies: String = ""
    @Published var foodBrand: String = ""
    @Published var chipID: String = "" {
        didSet {
            // 芯片号只保留数字，长度上限 15
            let filtered = String(chipID.filter(\.isNumber).prefix(15))
            if filtered != chipID {
                chipID = filtered
            }
        }
    }

    private let service: PetService
    private let editingPet: Pet?

    var isEditing: Bool { editingPet != nil }

    /// 名称非空且 ≤20 字
    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 20
    }

    init(service: PetService, pet: Pet? = nil) {
        self.service = service
        self.editingPet = pet
        if let pet = pet {
            name = pet.name
            species = pet.species
            breed = pet.breed ?? ""
            hasBirthday = pet.birthday != nil
            birthday = pet.birthday ?? Date()
            birthEstimated = pet.birthEstimated
            sex = pet.sex
            hasNeutered = pet.neutered != nil
            neutered = pet.neutered ?? false
            idealWeightText = pet.idealWeightKg.map { String($0) } ?? ""
            allergies = pet.allergies ?? ""
            foodBrand = pet.foodBrand ?? ""
            chipID = pet.chipID ?? ""
        }
    }

    /// 保存（新建或更新）。除名字与物种外全部字段可选。
    func save() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let idealWeight = Double(idealWeightText)
        // 生日开关关闭时不写入生日，"生日为估算"同时归零
        let resolvedBirthday = hasBirthday ? birthday : nil
        let resolvedBirthEstimated = hasBirthday ? birthEstimated : false

        if let pet = editingPet {
            pet.name = trimmedName
            pet.species = species
            pet.breed = breed.isEmpty ? nil : breed
            pet.birthday = resolvedBirthday
            pet.birthEstimated = resolvedBirthEstimated
            pet.sex = sex
            pet.neutered = hasNeutered ? neutered : nil
            pet.idealWeightKg = idealWeight
            pet.allergies = allergies.isEmpty ? nil : allergies
            pet.foodBrand = foodBrand.isEmpty ? nil : foodBrand
            pet.chipID = chipID.isEmpty ? nil : chipID
            try service.saveChanges(for: pet)
        } else {
            let pet = Pet(
                name: trimmedName,
                species: species,
                breed: breed.isEmpty ? nil : breed,
                birthday: resolvedBirthday,
                birthEstimated: resolvedBirthEstimated,
                sex: sex,
                neutered: hasNeutered ? neutered : nil,
                idealWeightKg: idealWeight,
                allergies: allergies.isEmpty ? nil : allergies,
                foodBrand: foodBrand.isEmpty ? nil : foodBrand,
                chipID: chipID.isEmpty ? nil : chipID
            )
            try service.createPet(pet)
        }
    }
}
