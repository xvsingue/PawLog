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
                await reconcileReminders()
            }
            .onChange(of: entitlements.isPro) { _, _ in
                // 升级/降级后按新的提醒上限重排通知
                Task { await reconcileReminders() }
            }
    }

    /// 提醒对账：按当前权益上限决定哪些提醒排通知
    private func reconcileReminders() async {
        let reminderService = ReminderService(
            context: modelContext,
            notificationService: NotificationService(),
            reminderLimit: { entitlements.reminderLimit }
        )
        await reminderService.reconcileAll()
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
