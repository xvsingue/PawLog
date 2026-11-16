//
//  TimelinePerformanceTests.swift
//  PawLogTests
//
//  M11：500 条记录的时间线数据准备与首屏布局耗时。
//  时间线使用 LazyVStack + LazyVGrid 分组，行不会在首屏一次性全部构建。
//

import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import PawLog

@MainActor
final class TimelinePerformanceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var pet: Pet!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
            Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        pet = Pet(name: "咪咪", species: .cat)
        context.insert(pet)

        let types = RecordType.allCases
        let now = Date()
        for index in 0..<500 {
            let date = now.addingTimeInterval(-Double(index) * 86_400 * 0.7)
            context.insert(Record(
                pet: pet,
                type: types[index % types.count],
                occurredAt: date,
                title: "记录 \(index)",
                note: index % 3 == 0 ? "复查结果稳定，精神食欲正常" : nil
            ))
        }
        try context.save()
    }

    override func tearDownWithError() throws {
        pet = nil
        context = nil
        container = nil
    }

    /// 分组与首屏数据准备应远低于 500ms
    func testGrouping500RecordsUnder500ms() throws {
        let records = try context.fetch(
            FetchDescriptor<Record>(
                predicate: ActivePredicates.records,
                sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
            )
        )
        XCTAssertEqual(records.count, 500)

        let start = CFAbsoluteTimeGetCurrent()
        let months = TimelineGrouping.group(records)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let groupedCount = months.flatMap { $0.days }.flatMap { $0.records }.count
        XCTAssertEqual(groupedCount, 500, "分组不得丢记录")
        print(String(format: "[M11-LIST] 500 条分组耗时 %.3fs", elapsed))
        XCTAssertLessThan(elapsed, 0.5, "500 条分组应 <500ms，实际 \(elapsed)s")
    }

    /// 首屏布局（含 LazyVStack 分组容器）应 <500ms
    func testTimelineFirstScreenLayoutUnder500ms() {
        let view = TimelineView(
            pet: pet,
            service: RecordService(context: context),
            reminderService: ReminderService(
                context: context,
                notificationService: NotificationService(center: UNUserNotificationCenterAdapter())
            ),
            onAdd: {}
        )

        var samples: [TimeInterval] = []
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            let controller = UIHostingController(rootView: AnyView(
                view
                    .modelContainer(container)
                    .environment(EntitlementService(context: context))
                    .environment(StoreKitService())
                    .environment(\.dynamicTypeSize, .large)
            ))
            controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            controller.view.layoutIfNeeded()
            _ = controller.sizeThatFits(in: CGSize(width: 390, height: 844))
            samples.append(CFAbsoluteTimeGetCurrent() - start)
        }

        let median = samples.sorted()[1]
        print(String(format: "[M11-LIST] 500 条首屏布局中位数 %.3fs", median))
        XCTAssertLessThan(median, 0.5, "500 条首屏布局应 <500ms，实际 \(median)s")
    }
}
