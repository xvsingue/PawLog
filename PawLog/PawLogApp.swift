//
//  PawLogApp.swift
//  PawLog
//
//  Created by Lennox on 2026/11/15.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct PawLogApp: App {
    /// 共享容器：App 与通知回调共用
    static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Pet.self,
            Record.self,
            WeightEntry.self,
            Reminder.self,
            Attachment.self, Entitlement.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var entitlements = EntitlementService(context: PawLogApp.sharedContainer.mainContext)
    @State private var storeKit = StoreKitService()

    init() {
        // 注册通知分类与回调，长按通知可直接标记完成/稍后提醒
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService().registerCategories()
    }

    var sharedModelContainer: ModelContainer { Self.sharedContainer }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let scene = ScreenshotScene.requested(from: ProcessInfo.processInfo.arguments) {
                ScreenshotRootView(scene: scene)
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
        .modelContainer(sharedModelContainer)
    }

    private var mainContent: some View {
        ContentView()
            .environment(entitlements)
            .environment(storeKit)
    }
}
