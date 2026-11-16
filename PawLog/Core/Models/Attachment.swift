//
//  Attachment.swift
//  PawLog
//
//  附件模型：图片或 PDF。PRD 中的 recordID 由 record 关系表达以支持级联删除。
//

import Foundation
import SwiftData

/// 附件类型
enum AttachmentKind: String, Codable, CaseIterable {
    case image
    case pdf
}

@Model
final class Attachment {
    var id: UUID
    var record: Record?
    var kind: AttachmentKind
    /// 相对路径 attachments/<recordID>/<uuid>.jpg；不存绝对路径
    var localPath: String
    var thumbnailData: Data?
    var createdAt: Date

    // MARK: - 同步元数据（默认值保证旧 store 可迁移）
    var localUpdatedAt: Date = Date.distantPast
    var deviceID: String = ""
    var deletedAt: Date?
    var changeTag: String = ""

    init(
        id: UUID = UUID(),
        record: Record? = nil,
        kind: AttachmentKind,
        localPath: String,
        thumbnailData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.record = record
        self.kind = kind
        self.localPath = localPath
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
    }
}
