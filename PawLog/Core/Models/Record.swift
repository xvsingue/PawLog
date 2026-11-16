//
//  Record.swift
//  PawLog
//
//  记录模型：7 类事件的通用结构，差异化字段存 payloadJSON。
//

import Foundation
import SwiftData

/// 记录类型
enum RecordType: String, Codable, CaseIterable {
    case vaccine
    case deworming
    case medication
    case visit
    case symptom
    case weight
    case daily
}

@Model
final class Record {
    var id: UUID
    var pet: Pet?
    var type: RecordType
    var occurredAt: Date
    var title: String
    var note: String?
    var payloadJSON: String
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - 同步元数据（默认值保证旧 store 可迁移）
    var localUpdatedAt: Date = Date.distantPast
    var deviceID: String = ""
    var deletedAt: Date?
    var changeTag: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Attachment.record)
    var attachments: [Attachment] = []

    init(
        id: UUID = UUID(),
        pet: Pet? = nil,
        type: RecordType,
        occurredAt: Date,
        title: String,
        note: String? = nil,
        payloadJSON: String = "",
        createdBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pet = pet
        self.type = type
        self.occurredAt = occurredAt
        self.title = title
        self.note = note
        self.payloadJSON = payloadJSON
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
