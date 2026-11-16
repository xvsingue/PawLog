//
//  AttachmentImageDecoder.swift
//  PawLog
//
//  附件图片解码。列表与查看器都通过 detached task 解码，
//  主线程只接收成品 CGImage，避免滚动时同步解码大图掉帧。
//

import Foundation
import CoreGraphics
import ImageIO

nonisolated enum AttachmentImageDecoder {
    /// 下采样解码，仅依赖 CoreGraphics / ImageIO
    static func decode(data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// 异步解码入口
nonisolated enum AttachmentThumbnailLoader {
    /// 后台解码内存中的数据。onDecode 仅用于观察解码所在线程（测试）。
    static func makeTask(
        data: Data,
        maxPixelSize: CGFloat,
        onDecode: (@Sendable (Bool) -> Void)? = nil
    ) -> Task<CGImage?, Never> {
        Task.detached(priority: .utility) {
            onDecode?(Thread.isMainThread)
            return AttachmentImageDecoder.decode(data: data, maxPixelSize: maxPixelSize)
        }
    }

    static func load(data: Data, maxPixelSize: CGFloat) async -> CGImage? {
        await makeTask(data: data, maxPixelSize: maxPixelSize).value
    }

    /// 后台读取文件并解码，用于全屏查看原图
    static func makeFileTask(url: URL, maxPixelSize: CGFloat) -> Task<CGImage?, Never> {
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return AttachmentImageDecoder.decode(data: data, maxPixelSize: maxPixelSize)
        }
    }
}
