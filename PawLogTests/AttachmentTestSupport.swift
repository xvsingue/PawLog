//
//  AttachmentTestSupport.swift
//  PawLogTests
//
//  附件测试的共用工具：生成 JPEG、读取像素尺寸、统计落盘文件。
//

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum AttachmentTestSupport {
    /// 生成带条纹的大图，避免纯色导致压缩后体积异常小
    static func makeJPEG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bitmap = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        bitmap.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 0.45, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.setFillColor(CGColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1))
        for x in stride(from: 0, to: width, by: 24) {
            bitmap.fill(CGRect(x: x, y: 0, width: 10, height: height))
        }
        let image = try XCTUnwrap(bitmap.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return (
            properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    static func storedFileCount(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return 0 }
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }
}
