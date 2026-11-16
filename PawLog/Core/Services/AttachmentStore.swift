//
//  AttachmentStore.swift
//  PawLog
//
//  附件文件的唯一存取入口：压缩、落盘、路径解析与物理删除。
//  存储位置：Documents/attachments/<recordID>/<uuid>.jpg。
//  Attachment.localPath 只保存相对路径（attachments/...），换设备按当前沙箱重建。
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 附件文件存储
nonisolated struct AttachmentStore: Sendable {
    /// 附件目录名，与备份内的相对路径前缀保持一致
    static let folderName = "attachments"
    /// 主图长边上限（px）
    static let maxImagePixelSize: CGFloat = 1600
    /// 缩略图长边上限（px）
    static let maxThumbnailPixelSize: CGFloat = 200
    /// 主图 JPEG 质量
    static let imageQuality: CGFloat = 0.8
    /// 缩略图 JPEG 质量
    static let thumbnailQuality: CGFloat = 0.5

    /// attachments 根目录（Documents/attachments）；测试可注入临时目录
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: - 路径

    /// 生成落库用相对路径：attachments/<recordID>/<fileName>
    static func relativePath(recordID: UUID, fileName: String) -> String {
        "\(Self.folderName)/\(recordID.uuidString)/\(fileName)"
    }

    /// 把存储路径解析为当前沙箱内的绝对 URL。
    /// 新数据是相对路径；旧数据可能是绝对路径，这里一并兼容。
    func url(forStoredPath path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        var relative = path
        if relative.hasPrefix(Self.folderName + "/") {
            relative.removeFirst(Self.folderName.count + 1)
        }
        return directory.appendingPathComponent(relative)
    }

    // MARK: - 写入

    /// 一次写入的结果
    struct StoredImage: Sendable {
        let relativePath: String
        let thumbnailData: Data
    }

    /// 压缩并写入主图，返回相对路径与缩略图。调用方应放在后台任务执行。
    /// 写入失败会删除已产生的文件，不留孤儿文件。
    func saveImage(_ data: Data, recordID: UUID) throws -> StoredImage {
        guard let main = Self.jpegData(from: data, maxPixelSize: Self.maxImagePixelSize, quality: Self.imageQuality),
              let thumbnail = Self.jpegData(from: data, maxPixelSize: Self.maxThumbnailPixelSize, quality: Self.thumbnailQuality) else {
            throw AttachmentError.unsupportedImage
        }

        let fileName = "\(UUID().uuidString).jpg"
        let relative = Self.relativePath(recordID: recordID, fileName: fileName)
        let url = url(forStoredPath: relative)

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try main.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw AttachmentError.writeFailed
        }

        return StoredImage(relativePath: relative, thumbnailData: thumbnail)
    }

    /// 物理删除附件文件。墓碑清理器与写入失败回滚共用。
    func removeFile(relativePath: String) {
        try? FileManager.default.removeItem(at: url(forStoredPath: relativePath))
    }

    // MARK: - 压缩

    /// 用 ImageIO 下采样并重新编码为 JPEG。只依赖 CoreGraphics / ImageIO，不使用 UIKit。
    static func jpegData(from data: Data, maxPixelSize: CGFloat, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// 附件操作错误
nonisolated enum AttachmentError: LocalizedError, Equatable {
    case unsupportedImage
    case writeFailed
    case limitReached

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return String(localized: "attachment.error.unsupported")
        case .writeFailed:
            return String(localized: "attachment.error.writeFailed")
        case .limitReached:
            return String(localized: "attachment.error.limit \(AttachmentService.maxPerRecord)")
        }
    }
}
