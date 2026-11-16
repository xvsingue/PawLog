//
//  WeightEntry.swift
//  PawLog
//
//  体重记录：独立表用于曲线查询，同日多次取最后一次。
//

import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID
    var pet: Pet?
    /// 体重（kg），精度 0.1
    var weightKg: Double
    /// 体况评分 1–9
    var bcs: Int?
    var date: Date
    var recordID: UUID?

    // MARK: - 同步元数据（默认值保证旧 store 可迁移）
    var localUpdatedAt: Date = Date.distantPast
    var deviceID: String = ""
    var deletedAt: Date?
    var changeTag: String = ""

    init(
        id: UUID = UUID(),
        pet: Pet? = nil,
        weightKg: Double,
        bcs: Int? = nil,
        date: Date = Date(),
        recordID: UUID? = nil
    ) {
        self.id = id
        self.pet = pet
        self.weightKg = weightKg
        self.bcs = bcs
        self.date = date
        self.recordID = recordID
    }
}
