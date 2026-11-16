//
//  SyncIdempotencyTests.swift
//  PawLogTests
//
//  幂等与并发复核：同一 changeTag 重复推送不产生重复数据；
//  两端同时创建同 id 实体时按 deviceID 决胜且只保留一条记录。
//

import XCTest
import SwiftData
@testable import PawLog

@MainActor
final class SyncIdempotencyTests: XCTestCase {
    private let baseTime = Date(timeIntervalSince1970: 1_770_000_000)

    func testPushSameChangeTagThreeTimesIsIdempotent() async throws {
        let root = SyncDevice.makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try SyncDevice(deviceID: "device-A", shareRootDirectory: root, now: baseTime)

        try a.petService.createPet(Pet(name: "咪咪", species: .cat))
        _ = try await a.engine.pushPending()

        let pushed = try XCTUnwrap(try a.transport.allChanges().first)
        let duplicate = LocalChange(
            entityName: pushed.entityName,
            entityID: pushed.entityID,
            operation: pushed.operation,
            changeTag: pushed.changeTag,
            deviceID: pushed.deviceID,
            updatedAt: pushed.updatedAt,
            deletedAt: pushed.deletedAt,
            payloadJSON: pushed.payloadJSON
        )

        for _ in 0..<3 {
            _ = try await a.transport.push([duplicate])
        }

        XCTAssertEqual(try a.transport.allChanges().count, 1)
        XCTAssertEqual(try a.context.fetch(FetchDescriptor<ChangeLog>()).count, 1)
        XCTAssertEqual(try a.petService.fetchPets().count, 1)
    }

    func testConcurrentCreateSameIDResolvedByDeviceID() async throws {
        let root = SyncDevice.makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try SyncDevice(deviceID: "device-A", shareRootDirectory: root, now: baseTime)
        let b = try SyncDevice(deviceID: "device-B", shareRootDirectory: root, now: baseTime)

        // 模拟 UUID 碰撞：两端用同一个 id 各建一只宠物
        let sharedID = UUID()
        try a.petService.createPet(Pet(id: sharedID, name: "A 宠物", species: .cat))
        try b.petService.createPet(Pet(id: sharedID, name: "B 宠物", species: .dog))

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()
        _ = try await a.engine.sync()

        let aPets = try a.petService.fetchPets()
        let bPets = try b.petService.fetchPets()
        XCTAssertEqual(aPets.count, 1)
        XCTAssertEqual(bPets.count, 1)
        // 时间相同，device-B 字典序更大，恒定由 B 胜出
        XCTAssertEqual(aPets.first?.name, "B 宠物")
        XCTAssertEqual(bPets.first?.name, "B 宠物")
        XCTAssertEqual(aPets.first?.id, sharedID)
        XCTAssertEqual(bPets.first?.id, sharedID)
    }
}
