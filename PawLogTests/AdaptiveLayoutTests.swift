//
//  AdaptiveLayoutTests.swift
//  PawLogTests
//
//  M11：5 个核心页面在 AX5（辅助功能最大字号）下的布局冒烟测试。
//  通过 UIHostingController 以固定宽度测量容器尺寸，宽度不得越过容器。
//

import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import PawLog

@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var pet: Pet!
    private var record: Record!

    private let phoneWidth: CGFloat = 390

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
            Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        pet = Pet(
            name: String(repeating: "超长宠物名", count: 4),
            species: .cat,
            breed: "英国短毛猫",
            idealWeightKg: 4.6
        )
        context.insert(pet)

        record = Record(
            pet: pet,
            type: .visit,
            occurredAt: Date(),
            title: String(repeating: "复查记录标题", count: 6),
            note: String(repeating: "复查结果稳定，精神食欲正常。", count: 4),
            payloadJSON: PayloadCoding.encode(
                VisitPayload(
                    hospital: String(repeating: "安心动物医院", count: 4),
                    diagnosis: String(repeating: "定期复查", count: 4)
                )
            )
        )
        context.insert(record)
        context.insert(WeightEntry(pet: pet, weightKg: 4.6, bcs: 5, date: Date()))
        context.insert(Reminder(pet: pet, kind: .vaccine, dueAt: Date().addingTimeInterval(86_400 * 10),
                                repeatRule: .none, enabled: true))
        try context.save()
    }

    override func tearDownWithError() throws {
        record = nil
        pet = nil
        context = nil
        container = nil
    }

    // MARK: - 5 个核心页面

    func testTimelineLayoutAtAccessibility5() {
        let view = TimelineView(
            pet: pet,
            service: RecordService(context: context),
            reminderService: reminderService,
            onAdd: {}
        )
        assertFits(view)
    }

    func testRecordDetailLayoutAtAccessibility5() {
        let view = NavigationStack {
            RecordDetailView(
                record: record,
                service: RecordService(context: context),
                reminderService: reminderService
            )
        }
        assertFits(view)
    }

    func testWeightTrendLayoutAtAccessibility5() {
        let view = WeightTrendView(pet: pet, service: WeightTrendService())
        assertFits(view)
    }

    func testReminderListLayoutAtAccessibility5() {
        let view = ReminderListView(
            pet: pet,
            reminderService: reminderService,
            recordService: RecordService(context: context)
        )
        assertFits(view)
    }

    func testSettingsLayoutAtAccessibility5() {
        assertFits(SettingsView())
    }

    // MARK: - 行级与字号

    /// 超长标题 / 医院名在 AX5 下单行截断，不撑破行容器
    func testTimelineRowLongTextFitsWidthAtAccessibility5() {
        let size = measure(TimelineRow(record: record), width: 320)
        XCTAssertLessThanOrEqual(size.width, 321, "时间线行不得横向溢出")
        XCTAssertGreaterThan(size.height, 44, "AX5 下行高应随字号增长")
    }

    /// 字号令牌必须随 Dynamic Type 放大
    func testTypographyScalesWithDynamicType() {
        let normal = measure(Text("体重 4.60 kg").font(Theme.Typography.body), width: 390,
                             dynamicType: .large)
        let ax5 = measure(Text("体重 4.60 kg").font(Theme.Typography.body), width: 390,
                          dynamicType: .accessibility5)
        XCTAssertGreaterThan(ax5.height, normal.height * 1.5, "AX5 字号应显著大于默认字号")
    }

    // MARK: - 工具

    private var reminderService: ReminderService {
        ReminderService(
            context: context,
            notificationService: NotificationService(center: UNUserNotificationCenterAdapter())
        )
    }

    private func assertFits<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        let size = measure(view, width: phoneWidth)
        XCTAssertGreaterThan(size.width, 0, "页面应参与布局", file: file, line: line)
        XCTAssertLessThanOrEqual(size.width, phoneWidth + 1, "页面不得横向溢出", file: file, line: line)
    }

    private func measure<V: View>(
        _ view: V,
        width: CGFloat,
        dynamicType: DynamicTypeSize = .accessibility5
    ) -> CGSize {
        let root = AnyView(
            view
                .modelContainer(container)
                .environment(EntitlementService(context: context))
                .environment(\.dynamicTypeSize, dynamicType)
        )
        let controller = UIHostingController(rootView: root)
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
        controller.view.layoutIfNeeded()
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
