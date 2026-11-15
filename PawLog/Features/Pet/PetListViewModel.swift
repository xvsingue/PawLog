//
//  PetListViewModel.swift
//  PawLog
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class PetListViewModel: ObservableObject {
    @Published var pets: [Pet] = []
    @Published var errorMessage: String?

    let service: PetService

    init(service: PetService) {
        self.service = service
    }

    func loadPets() {
        do {
            pets = try service.fetchPets()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "pet.list.error.load")
        }
    }

    /// 删除宠物，返回被删除的 Record 条数
    @discardableResult
    func deletePet(_ pet: Pet) -> Int {
        do {
            let count = try service.deletePet(pet)
            loadPets()
            return count
        } catch {
            errorMessage = String(localized: "pet.list.error.delete")
            return 0
        }
    }

    /// 记录条数（仅 Record），用于删除确认提示
    func recordCount(for pet: Pet) -> Int {
        service.countRecords(for: pet)
    }

    /// 重排宠物顺序。数据源本身可重排，M2 接入拖动排序时直接调用。
    func movePets(fromOffsets source: IndexSet, toOffset destination: Int) {
        pets.move(fromOffsets: source, toOffset: destination)
    }
}
