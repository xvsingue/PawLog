//
//  ContentView.swift
//  PawLog
//
//  应用根视图：首页（宠物切换 + 时间线）。启动时执行一次提醒对账。
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var didReconcile = false

    var body: some View {
        HomeView()
            .task {
                guard !didReconcile else { return }
                didReconcile = true
                let notificationService = NotificationService()
                let reminderService = ReminderService(
                    context: modelContext,
                    notificationService: notificationService
                )
                await reminderService.reconcileAll()
            }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
        configurations: config
    )
    return ContentView()
        .modelContainer(container)
}
