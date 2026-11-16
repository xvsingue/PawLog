//
//  DebugScreenshotSupport.swift
//  PawLog
//
//  仅 DEBUG：通过 -uiScreenshot <scene> 进入指定页面并注入内存示例数据。
//  Release 编译时整个文件被移除，示例数据不会写入用户数据库。
//

#if DEBUG
import SwiftUI
import SwiftData

/// 截图场景
enum ScreenshotScene: String, CaseIterable {
    case home
    case timeline
    case recordDetail
    case quickRecord
    case weightTrend
    case summary
    case reminders
    case settings
    case paywall

    /// 解析启动参数 `-uiScreenshot <scene>`
    static func requested(from arguments: [String]) -> ScreenshotScene? {
        guard let index = arguments.firstIndex(of: "-uiScreenshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return ScreenshotScene(rawValue: arguments[index + 1])
    }
}

@MainActor
enum ScreenshotSampleData {
    /// 纯内存容器：不触碰用户持久化数据
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
                configurations: config
            )
        } catch {
            fatalError("Screenshot container failed: \(error)")
        }
        seed(context: container.mainContext)
        return container
    }

    private static func seed(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }
        func daysAhead(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: now) ?? now
        }

        let pet = Pet(
            name: "咪咪",
            species: .cat,
            breed: "英短",
            birthday: calendar.date(byAdding: .year, value: -3, to: now),
            sex: .female,
            neutered: true,
            idealWeightKg: 4.6,
            allergies: "鸡肉",
            chipID: "900123456789012"
        )
        context.insert(pet)

        let samples: [(RecordType, Date, String)] = [
            (.weight, now, "4.6 kg"),
            (.symptom, now, "轻微呕吐"),
            (.vaccine, daysAgo(1), "猫三联"),
            (.daily, daysAgo(1), "精神不错"),
            (.visit, daysAgo(2), "年度体检"),
            (.deworming, daysAgo(2), "体内驱虫"),
        ]
        for (type, date, title) in samples {
            context.insert(Record(pet: pet, type: type, occurredAt: date, title: title))
        }

        let weights: [(Double, Int, Int)] = [
            (4.80, 4, 20),
            (4.75, 5, 10),
            (4.62, 5, 3),
            (4.60, 5, 0),
        ]
        for (kg, bcs, offset) in weights {
            context.insert(WeightEntry(pet: pet, weightKg: kg, bcs: bcs, date: daysAgo(offset)))
        }

        let reminders: [(ReminderKind, Date)] = [
            (.vaccine, daysAhead(14)),
            (.deworming, daysAhead(30)),
            (.visit, daysAhead(60)),
        ]
        for (kind, due) in reminders {
            context.insert(Reminder(pet: pet, kind: kind, dueAt: due, repeatRule: .none, enabled: true))
        }

        try? context.save()
    }

    static func samplePaywallProducts() -> [PaywallProduct] {
        [
            PaywallProduct(id: StoreKitService.monthlyID, title: "爪记 Pro 月订阅", price: "¥18.00", period: "按月订阅", product: nil),
            PaywallProduct(id: StoreKitService.yearlyID, title: "爪记 Pro 年订阅", price: "¥98.00", period: "按年订阅", product: nil),
            PaywallProduct(id: StoreKitService.lifetimeID, title: "爪记 Pro 终身", price: "¥198.00", period: "一次性购买", product: nil),
        ]
    }
}

/// 截图专用根视图
struct ScreenshotRootView: View {
    let scene: ScreenshotScene

    private let container: ModelContainer
    @State private var entitlements: EntitlementService
    @State private var storeKit = StoreKitService()

    init(scene: ScreenshotScene) {
        self.scene = scene
        let container = ScreenshotSampleData.makeContainer()
        self.container = container
        _entitlements = State(initialValue: EntitlementService(context: container.mainContext))
    }

    private var pet: Pet? {
        try? container.mainContext.fetch(
            FetchDescriptor<Pet>(predicate: ActivePredicates.pets)
        ).first
    }

    var body: some View {
        content
            .modelContainer(container)
            .environment(entitlements)
            .environment(storeKit)
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .home, .timeline:
            HomeView()
        case .recordDetail:
            if let record = try? container.mainContext.fetch(
                FetchDescriptor<Record>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
            ).first {
                NavigationStack {
                    RecordDetailView(
                        record: record,
                        service: RecordService(context: container.mainContext),
                        reminderService: ReminderService(
                            context: container.mainContext,
                            notificationService: NotificationService()
                        )
                    )
                }
            }
        case .quickRecord:
            if let pet {
                NavigationStack {
                    QuickRecordSheet(
                        pet: pet,
                        service: RecordService(context: container.mainContext),
                        reminderService: ReminderService(
                            context: container.mainContext,
                            notificationService: NotificationService()
                        ),
                        debugType: .vaccine
                    )
                }
            }
        case .weightTrend:
            if let pet {
                WeightTrendView(pet: pet, service: WeightTrendService())
            }
        case .summary:
            if let pet {
                SummaryView(pet: pet)
            }
        case .reminders:
            if let pet {
                ReminderListView(
                    pet: pet,
                    reminderService: ReminderService(
                        context: container.mainContext,
                        notificationService: NotificationService()
                    ),
                    recordService: RecordService(context: container.mainContext)
                )
            }
        case .settings:
            SettingsView()
        case .paywall:
            PaywallView(sampleProducts: ScreenshotSampleData.samplePaywallProducts())
        }
    }
}
#endif
