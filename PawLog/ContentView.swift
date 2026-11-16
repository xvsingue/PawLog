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
    @Environment(EntitlementService.self) private var entitlements
    @Environment(StoreKitService.self) private var storeKit
    @State private var didReconcile = false

    var body: some View {
        HomeView()
            .task {
                // 延迟交易、退款、撤销统一写回权益
                storeKit.onEvent = { entitlements.apply($0) }
                storeKit.startObservingUpdates()

                guard !didReconcile else { return }
                didReconcile = true
                entitlements.refresh()
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
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
        configurations: config
    )
    return ContentView()
        .modelContainer(container)
        .environment(EntitlementService(context: container.mainContext))
        .environment(StoreKitService())
}
