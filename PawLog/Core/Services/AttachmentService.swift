//
//  AttachmentService.swift
//  PawLog
//
//  附件业务：单条记录最多 3 张、后台压缩落盘、墓碑删除。
//  磁盘文件的最终物理删除由 TombstonePurger 统一执行，避免其它设备还没同步到删除。
//

import Foundation
import SwiftData

@MainActor
final class AttachmentService {
    /// 单条记录最多照片数
    nonisolated static let maxPerRecord = 3

    private let context: ModelContext
    private let store: AttachmentStore
    private let changes: ChangeLogService
    private let clock: Clock

    init(
        context: ModelContext,
        attachmentDirectory: URL? = nil,
        deviceID: String = DeviceIdentity.current(),
        clock: Clock = SystemClock()
    ) {
        self.context = context
        let store = AttachmentStore(directory: attachmentDirectory)
        self.store = store
        self.clock = clock
        self.changes = ChangeLogService(
            context: context,
            deviceID: deviceID,
            clock: clock,
            attachmentDirectory: store.directory
        )
    }

    // MARK: - 读

    /// 记录下未删除的附件，按创建时间升序
    func attachments(for record: Record) -> [Attachment] {
        record.attachments
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
    }

    /// 附件的当前沙箱绝对路径，仅供查看与解码使用
    func fileURL(for attachment: Attachment) -> URL {
        store.url(forStoredPath: attachment.localPath)
    }

    // MARK: - 写

    /// 添加照片。压缩与写盘在后台执行；超限在写文件之前拒绝。
    @discardableResult
    func addImage(_ data: Data, to record: Record) async throws -> Attachment {
        guard attachments(for: record).count < Self.maxPerRecord else {
            throw AttachmentError.limitReached
        }

        let store = self.store
        let recordID = record.id
        let stored = try await Task.detached(priority: .userInitiated) {
            try store.saveImage(data, recordID: recordID)
        }.value

        let attachment = Attachment(
            record: record,
            kind: .image,
            localPath: stored.relativePath,
            thumbnailData: stored.thumbnailData,
            createdAt: clock.now
        )
        context.insert(attachment)

        do {
            try changes.record(attachment, kind: .attachment, operation: .create)
            try context.save()
            return attachment
        } catch {
            // 数据库写入失败时回滚文件，避免留下孤儿文件
            context.delete(attachment)
            store.removeFile(relativePath: stored.relativePath)
            throw error
        }
    }

    /// 删除照片：写墓碑并记录变更，磁盘文件留给 TombstonePurger。
    func delete(_ attachment: Attachment) throws {
        let now = clock.now
        try changes.record(attachment, kind: .attachment, operation: .delete, at: now)
        attachment.deletedAt = now
        try context.save()
    }
}
