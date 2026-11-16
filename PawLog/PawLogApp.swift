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
            Attachment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 注册通知分类与回调，长按通知可直接标记完成/稍后提醒
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService().registerCategories()
    }

    var sharedModelContainer: ModelContainer { Self.sharedContainer }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
