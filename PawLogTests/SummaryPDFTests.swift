//
//  SummaryPDFTests.swift
//  PawLogTests
//
//  就诊摘要导出：分页、头部信息、90 天窗口、空数据、长图宽度与耗时。
//

import XCTest
import SwiftData
import PDFKit
import UIKit
@testable import PawLog

@MainActor
final class SummaryPDFTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var recordService: RecordService!
    private var pet: Pet!
    private var now: Date!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        calendar = Calendar(identifier: .gregorian)
        now = Date()
        recordService = RecordService(context: context)
        pet = Pet(name: "咪咪", species: .cat, breed: "英短", chipID: "900123456789012")
        context.insert(pet)
        try context.save()
    }

    override func tearDownWithError() throws {
        recordService = nil
        pet = nil
        context = nil
        container = nil
        calendar = nil
        now = nil
    }

    // MARK: - 辅助

    @discardableResult
    private func addVisit(title: String, diagnosis: String = "定期复查", daysAgo: Int) throws -> Record {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return try recordService.create(
            pet: pet,
            type: .visit,
            occurredAt: date,
            title: title,
            note: nil,
            payloadJSON: PayloadCoding.encode(VisitPayload(hospital: "安心动物医院", diagnosis: diagnosis)),
            now: now
        )
    }

    private func snapshot() -> SummarySnapshot {
        SummarySnapshotBuilder.make(pet: pet, now: now, calendar: calendar)
    }

    private func pdfString(_ data: Data) throws -> String {
        let document = try XCTUnwrap(PDFDocument(data: data))
        return document.string ?? ""
    }

    // MARK: - 分页

    /// 数据量跨页时分页数正确
    func testPageCountGrowsWithRecords() throws {
        let service = SummaryPDFService(clock: FixedClock(now))

        try addVisit(title: "复查一", daysAgo: 5)
        try addVisit(title: "复查二", daysAgo: 6)
        let small = try XCTUnwrap(PDFDocument(data: service.renderPDF(snapshot())))
        XCTAssertEqual(small.pageCount, 1, "少量数据应在一页内")

        for index in 0..<40 {
            try addVisit(title: "复查记录 \(index)", daysAgo: index + 7)
        }
        let large = try XCTUnwrap(PDFDocument(data: service.renderPDF(snapshot())))
        XCTAssertGreaterThan(large.pageCount, 1, "大量数据应跨页")
    }

    // MARK: - 头部

    /// 头部包含宠物名与芯片号
    func testHeaderContainsPetNameAndChipID() throws {
        let service = SummaryPDFService(clock: FixedClock(now))
        let text = try pdfString(service.renderPDF(snapshot()))

        XCTAssertTrue(text.contains("咪咪"))
        XCTAssertTrue(text.contains("900123456789012"))
    }

    /// 每页页脚文案固定且页码存在
    func testFooterDisclaimerAndPageNumber() throws {
        let service = SummaryPDFService(clock: FixedClock(now))
        for index in 0..<30 {
            try addVisit(title: "复查记录 \(index)", daysAgo: index + 1)
        }
        let text = try pdfString(service.renderPDF(snapshot()))
        // PDFKit 抽取时可能在中文标点后插入空格，比对时忽略空白
        let compact = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")

        XCTAssertTrue(
            compact.contains("本摘要由用户自行记录生成，仅供就诊参考，不构成诊断意见。"),
            "页脚提取结果：\(text.suffix(200))"
        )
        XCTAssertTrue(compact.contains("第1页/共"), "页码提取结果：\(text.suffix(80))")
    }

    // MARK: - 90 天窗口

    /// 只包含 90 天内的数据
    func testOnlyLast90DaysIncluded() throws {
        try addVisit(title: "旧记录OUTDATED", daysAgo: 120)
        try addVisit(title: "新记录RECENT", daysAgo: 10)

        let service = SummaryPDFService(clock: FixedClock(now))
        let text = try pdfString(service.renderPDF(snapshot()))

        XCTAssertTrue(text.contains("新记录RECENT"))
        XCTAssertFalse(text.contains("旧记录OUTDATED"), "超过 90 天的记录不应出现在摘要中")
    }

    // MARK: - 空数据

    /// 无记录也能导出，且不生成空文件
    func testEmptyDataStillExports() throws {
        let service = SummaryPDFService(clock: FixedClock(now))
        let data = service.renderPDF(snapshot())

        XCTAssertFalse(data.isEmpty, "不得生成空文件")
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        XCTAssertTrue((document.string ?? "").contains("近 90 天暂无记录"))
    }

    // MARK: - 长图

    /// 长图宽度为 1080px
    func testLongImageWidthIs1080() throws {
        try addVisit(title: "复查一", daysAgo: 3)
        let service = SummaryPDFService(clock: FixedClock(now))
        let data = service.renderLongImage(snapshot())

        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(Int(image.size.width), 1080)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// 长图导出耗时小于 1.5 秒（XCTest measure + 单次实测）
    func testLongImageExportPerformance() throws {
        for index in 0..<60 {
            try addVisit(title: "复查记录 \(index)", diagnosis: "复查结果稳定", daysAgo: index)
        }
        let service = SummaryPDFService(clock: FixedClock(now))
        let built = snapshot()

        measure {
            MainActor.assumeIsolated {
                _ = service.renderLongImage(built)
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        _ = service.renderLongImage(built)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertLessThan(elapsed, 1.5, "单次长图导出应小于 1.5 秒，实际 \(elapsed)s")
    }

    // MARK: - 文件名

    /// 文件名格式：宠物名_摘要_yyyyMMdd.pdf
    func testPDFFileNameFormat() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        let service = SummaryPDFService(clock: FixedClock(date))

        let name = service.pdfFileName(petName: "咪咪")

        XCTAssertTrue(name.hasPrefix("咪咪_"), "文件名应以宠物名开头：\(name)")
        XCTAssertTrue(name.hasSuffix("_20261116.pdf"), "文件名应含日期后缀：\(name)")
    }
}
