//
//  SummaryPDFService.swift
//  PawLog
//
//  就诊摘要导出：A4 PDF 与 1080px 长图。
//  本文件是本月唯一允许使用 UIKit 的位置，不得扩散到其他模块。
//

import Foundation
import UIKit
import SwiftUI

/// 就诊摘要导出服务
@MainActor
final class SummaryPDFService {
    /// A4 尺寸（pt）
    static let pageSize = CGSize(width: 595, height: 842)
    /// 页边距（pt）
    static let margin: CGFloat = 40
    /// 长图宽度（px）
    static let longImageWidth: CGFloat = 1080

    private let clock: Clock

    init(clock: Clock = SystemClock()) {
        self.clock = clock
    }

    // MARK: - 文件名

    func pdfFileName(petName: String) -> String {
        fileName(petName: petName, ext: "pdf")
    }

    func imageFileName(petName: String) -> String {
        fileName(petName: petName, ext: "png")
    }

    private func fileName(petName: String, ext: String) -> String {
        "\(sanitized(petName))_\(String(localized: "summary.file.suffix"))_\(dateStamp()).\(ext)"
    }

    private func dateStamp() -> String {
        clock.now.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
    }

    private func sanitized(_ name: String) -> String {
        let cleaned = name.trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? String(localized: "summary.file.unnamed") : cleaned
    }

    // MARK: - PDF

    /// 生成 A4 PDF
    func renderPDF(_ snapshot: SummarySnapshot) -> Data {
        let contentWidth = Self.pageSize.width - Self.margin * 2
        let blocks = makeBlocks(snapshot, contentWidth: contentWidth)
        let contentHeight = Self.pageSize.height - Self.margin * 2 - Self.footerHeight
        let pages = paginate(blocks, contentWidth: contentWidth, contentHeight: contentHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                drawFooter(pageIndex: index + 1, totalPages: pages.count, contentWidth: contentWidth)
                var y = Self.margin
                for block in page {
                    y = draw(block, at: y, width: contentWidth, context: context.cgContext)
                }
            }
        }
    }

    /// 写入临时目录，返回可分享的 URL
    func writePDF(_ snapshot: SummarySnapshot, petName: String) throws -> URL {
        try write(renderPDF(snapshot), fileName: pdfFileName(petName: petName))
    }

    // MARK: - 长图
    /// 生成 1080px 宽长图（按快照的 90 天内容拼接）
    func renderLongImage(_ snapshot: SummarySnapshot) -> Data {
        let contentWidth = Self.longImageWidth - Self.margin * 2
        let blocks = makeBlocks(snapshot, contentWidth: contentWidth)
        let contentHeight = blocks.reduce(0) { $0 + blockHeight($1, width: contentWidth) }
        let height = max(contentHeight + Self.margin * 2, 400)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: Self.longImageWidth, height: height),
            format: format
        )
        return renderer.pngData { context in
            UIColor(Theme.Palette.card).setFill()
            context.fill(CGRect(x: 0, y: 0, width: Self.longImageWidth, height: height))
            var y = Self.margin
            for block in blocks {
                y = draw(block, at: y, width: contentWidth, context: context.cgContext)
            }
        }
    }

    func writeLongImage(_ snapshot: SummarySnapshot, petName: String) throws -> URL {
        try write(renderLongImage(snapshot), fileName: imageFileName(petName: petName))
    }

    private func write(_ data: Data, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private enum Block {
        case text(NSAttributedString, spacing: CGFloat)
        case rule(spacing: CGFloat)
    }

    private static let bodyFont = UIFont.systemFont(ofSize: 11)
    private static let captionFont = UIFont.systemFont(ofSize: 9)
    private static let sectionFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let titleFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    private static let footerHeight: CGFloat = 40
    private var primaryColor: UIColor { UIColor(Theme.Palette.textPrimary) }
    private var secondaryColor: UIColor { UIColor(Theme.Palette.textSecondary) }
    private var ruleColor: UIColor { UIColor(Theme.Palette.textTertiary).withAlphaComponent(0.3) }

    private func makeBlocks(_ snapshot: SummarySnapshot, contentWidth: CGFloat) -> [Block] {
        var blocks: [Block] = []

        blocks.append(line(String(localized: "summary.title"), font: Self.titleFont, spacing: Theme.Spacing.md))
        let generated = snapshot.generatedAt.formatted(.dateTime.year().month().day())
        blocks.append(line(
            String(localized: "summary.generatedAt \(generated)"),
            font: Self.captionFont,
            color: secondaryColor,
            spacing: Theme.Spacing.xxl
        ))

        for (label, value) in headerRows(snapshot.header) {
            blocks.append(line("\(label)\u{FF1A}\(value)", spacing: Theme.Spacing.xs))
        }
        blocks.append(.rule(spacing: Theme.Spacing.lg))

        blocks.append(sectionTitle("summary.section.records"))
        appendEntries(snapshot.records, emptyKey: "summary.empty.records", to: &blocks)
        blocks.append(.rule(spacing: Theme.Spacing.lg))

        blocks.append(sectionTitle("summary.section.weight"))
        if let change = snapshot.weightChange {
            blocks.append(line(
                String(localized: "summary.weight.summary \(change.startText) \(change.endText) \(change.changeText)"),
                spacing: Theme.Spacing.md
            ))
        } else {
            blocks.append(line(String(localized: "summary.value.none"), color: secondaryColor, spacing: Theme.Spacing.md))
        }
        blocks.append(.rule(spacing: Theme.Spacing.lg))

        blocks.append(sectionTitle("summary.section.medicationVisits"))
        appendEntries(snapshot.medicationAndVisits, emptyKey: "summary.value.none", to: &blocks)

        return blocks
    }

    /// 记录列表；为空时展示占位文案
    private func appendEntries(_ entries: [SummarySnapshot.Entry], emptyKey: String, to blocks: inout [Block]) {
        guard !entries.isEmpty else {
            blocks.append(line(String(localized: String.LocalizationValue(emptyKey)), color: secondaryColor, spacing: Theme.Spacing.md))
            return
        }
        for entry in entries {
            let dateText = entry.date.formatted(.dateTime.year().month().day())
            blocks.append(line("\(dateText)   \(entry.typeTitle)   \(entry.title)", spacing: Theme.Spacing.xs))
            if !entry.detail.isEmpty {
                blocks.append(line(entry.detail, font: Self.captionFont, color: secondaryColor, spacing: Theme.Spacing.sm))
            }
        }
    }

    private func headerRows(_ header: SummarySnapshot.Header) -> [(String, String)] {
        [
            (String(localized: "summary.header.pet"), header.petName),
            (String(localized: "summary.header.speciesBreed"), header.speciesBreed),
            (String(localized: "summary.header.sex"), header.sex),
            (String(localized: "summary.header.age"), header.age),
            (String(localized: "summary.header.chipID"), header.chipID),
            (String(localized: "summary.header.weight"), header.weight),
            (String(localized: "summary.header.allergies"), header.allergies)
        ]
    }

    private func sectionTitle(_ key: String) -> Block {
        line(String(localized: String.LocalizationValue(key)), font: Self.sectionFont, spacing: Theme.Spacing.sm)
    }

    private func line(
        _ text: String,
        font: UIFont? = nil,
        color: UIColor? = nil,
        spacing: CGFloat
    ) -> Block {
        .text(attributed(text, font: font ?? Self.bodyFont, color: color ?? primaryColor), spacing: spacing)
    }

    private func attributed(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    // MARK: - 分页与绘制

    private func paginate(_ blocks: [Block], contentWidth: CGFloat, contentHeight: CGFloat) -> [[Block]] {
        var pages: [[Block]] = []
        var current: [Block] = []
        var used: CGFloat = 0

        for block in blocks {
            let height = blockHeight(block, width: contentWidth)
            if used + height > contentHeight, !current.isEmpty {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(block)
            used += height
        }
        if !current.isEmpty || pages.isEmpty {
            pages.append(current)
        }
        return pages
    }

    private func blockHeight(_ block: Block, width: CGFloat) -> CGFloat {
        switch block {
        case .text(let text, let spacing): return textHeight(text, width: width) + spacing
        case .rule(let spacing): return 1 + spacing
        }
    }

    private func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height.rounded(.up)
    }

    /// 绘制一个块，返回下一个块的起始 y
    @discardableResult
    private func draw(_ block: Block, at y: CGFloat, width: CGFloat, context: CGContext) -> CGFloat {
        switch block {
        case .text(let text, let spacing):
            let height = textHeight(text, width: width)
            text.draw(
                with: CGRect(x: Self.margin, y: y, width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            return y + height + spacing
        case .rule(let spacing):
            context.setStrokeColor(ruleColor.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: Self.margin, y: y + 0.5))
            context.addLine(to: CGPoint(x: Self.pageSize.width - Self.margin, y: y + 0.5))
            context.strokePath()
            return y + 1 + spacing
        }
    }

    /// 页脚：固定免责声明 + 页码
    private func drawFooter(pageIndex: Int, totalPages: Int, contentWidth: CGFloat) {
        let footerY = Self.pageSize.height - Self.margin - Self.footerHeight + Theme.Spacing.sm

        let disclaimer = attributed(
            String(localized: "summary.disclaimer"),
            font: Self.captionFont,
            color: secondaryColor
        )
        let disclaimerHeight = textHeight(disclaimer, width: contentWidth - 110)
        disclaimer.draw(
            with: CGRect(x: Self.margin, y: footerY, width: contentWidth - 110, height: disclaimerHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let pageText = attributed(
            String(localized: "summary.page.number \(pageIndex) \(totalPages)"),
            font: Self.captionFont,
            color: secondaryColor
        )
        pageText.draw(at: CGPoint(
            x: Self.pageSize.width - Self.margin - pageText.size().width,
            y: footerY
        ))
    }
}
