//
//  ScreenshotExportTests.swift
//  PawLogTests
//
//  M11：用 UIHostingController 离屏渲染 5 个核心页面的 AX5 与深色截图，
//  输出到测试进程的临时目录，供汇报归档。
//

import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import PawLog

@MainActor
final class ScreenshotExportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var pet: Pet!
    private var record: Record!

    private let size = CGSize(width: 390, height: 844)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
            Entitlement.self, ChangeLog.self, ConflictLog.self,
            configurations: config
        )
        context = container.mainContext
        pet = Pet(
            name: "咪咪",
            species: .cat,
            breed: "英国短毛猫",
            birthday: Calendar.current.date(byAdding: .year, value: -3, to: Date()),
            sex: .female,
            neutered: true,
            idealWeightKg: 4.6,
            allergies: "鸡肉",
            chipID: "900123456789012"
        )
        context.insert(pet)

        let now = Date()
        record = Record(
            pet: pet,
            type: .visit,
            occurredAt: now,
            title: "年度体检",
            note: "复查结果稳定，精神食欲正常。",
            payloadJSON: PayloadCoding.encode(
                VisitPayload(hospital: "安心动物医院", doctor: "李医生", diagnosis: "定期复查")
            )
        )
        context.insert(record)
        context.insert(Record(pet: pet, type: .vaccine, occurredAt: now.addingTimeInterval(-86_400),
                              title: "猫三联"))
        context.insert(Record(pet: pet, type: .weight, occurredAt: now.addingTimeInterval(-2 * 86_400),
                              title: "4.6 kg"))
        for (index, kg) in [4.8, 4.75, 4.62, 4.6].enumerated() {
            context.insert(WeightEntry(pet: pet, weightKg: kg, bcs: 5,
                                       date: now.addingTimeInterval(-Double(index * 10) * 86_400)))
        }
        for (kind, days) in [(ReminderKind.vaccine, 14), (.deworming, 30), (.visit, 60)] {
            context.insert(Reminder(pet: pet, kind: kind,
                                    dueAt: now.addingTimeInterval(Double(days) * 86_400),
                                    repeatRule: .none, enabled: true))
        }
        try context.save()
    }

    override func tearDownWithError() throws {
        record = nil
        pet = nil
        context = nil
        container = nil
    }

    func testExportAccessibilityAndDarkScreenshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PawLogScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let reminderService = ReminderService(
            context: context,
            notificationService: NotificationService(center: UNUserNotificationCenterAdapter())
        )

        let pages: [(String, AnyView)] = [
            ("timeline", AnyView(TimelineView(
                pet: pet,
                service: RecordService(context: context),
                reminderService: reminderService,
                onAdd: {}
            ))),
            ("recordDetail", AnyView(NavigationStack {
                RecordDetailView(
                    record: record,
                    service: RecordService(context: context),
                    reminderService: reminderService
                )
            })),
            ("weightTrend", AnyView(WeightTrendView(pet: pet, service: WeightTrendService()))),
            ("reminders", AnyView(ReminderListView(
                pet: pet,
                reminderService: reminderService,
                recordService: RecordService(context: context)
            ))),
            ("settings", AnyView(SettingsView()))
        ]

        for (name, page) in pages {
            try snapshot(page, dynamicType: .accessibility5, colorScheme: .light,
                         to: directory.appendingPathComponent("ax5-\(name).png"))
            try snapshot(page, dynamicType: .large, colorScheme: .dark,
                         to: directory.appendingPathComponent("dark-\(name).png"))
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 10)
        print("[M11-SHOTS] \(directory.path)")
    }

    private func snapshot(
        _ view: AnyView,
        dynamicType: DynamicTypeSize,
        colorScheme: ColorScheme,
        to url: URL
    ) throws {
        let root = view
            .modelContainer(container)
            .environment(EntitlementService(context: context))
            .environment(\.dynamicTypeSize, dynamicType)
            .environment(\.colorScheme, colorScheme)
        let controller = UIHostingController(rootView: root)
        controller.view.frame = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: url, options: .atomic)
    }
}
