//
//  PetSortOrderTests.swift
//  PawLogTests
//
//  验证拖动排序持久化：save 后新建 ModelContext 重新 fetch，顺序应与移动结果一致。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class PetSortOrderTests: XCTestCase {
    private var container: ModelContainer!
    private var service: PetService!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        service = PetService(context: container.mainContext)
    }

    override func tearDownWithError() throws {
        service = nil
        container = nil
    }

    /// 新建宠物时 sortIndex 依次递增
    func testCreatePetAssignsIncrementingSortIndex() throws {
        for name in ["A", "B", "C"] {
            try service.createPet(Pet(name: name, species: .cat))
        }

        let indices = try service.fetchPets().map(\.sortIndex)
        XCTAssertEqual(indices, [0, 1, 2])
    }

    /// 移动后重新建 ModelContext 再 fetch，顺序保持
    func testMovePetsPersistsOrder() throws {
        for name in ["A", "B", "C"] {
            try service.createPet(Pet(name: name, species: .cat))
        }
        XCTAssertEqual(try service.fetchPets().map(\.name), ["A", "B", "C"])

        // 把最后一只拖到最前
        try service.movePets(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        // 用同一个 store 新建 ModelContext 重新读取
        let freshContext = ModelContext(container)
        let freshService = PetService(context: freshContext)
        let names = try freshService.fetchPets().map(\.name)

        XCTAssertEqual(names, ["C", "A", "B"])
        XCTAssertEqual(try freshService.fetchPets().map(\.sortIndex), [0, 1, 2])
    }

    /// 多选移动：把前两只移到末尾
    func testMoveMultiplePetsPersistsOrder() throws {
        for name in ["A", "B", "C", "D"] {
            try service.createPet(Pet(name: name, species: .cat))
        }

        try service.movePets(fromOffsets: IndexSet([0, 1]), toOffset: 4)

        let freshService = PetService(context: ModelContext(container))
        XCTAssertEqual(try freshService.fetchPets().map(\.name), ["C", "D", "A", "B"])
    }
}
