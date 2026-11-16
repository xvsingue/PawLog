//
//  EntitlementService.swift
//  PawLog
//
//  权益判定唯一入口：界面层只读这里的 isPro 与限额，不自行判断。
//

import Foundation
import SwiftData
import Observation

/// 一次购买/续订事件（与 StoreKit 类型解耦，便于测试）
struct PurchaseEvent: Equatable {
    var productID: String
    var purchasedAt: Date
    var expiresAt: Date?
    var revokedAt: Date?
}

@MainActor
@Observable
final class EntitlementService {
    // MARK: - 限额常量

    /// 免费版宠物上限
    static let freePetLimit = 1
    /// Pro 宠物上限
    static let proPetLimit = 20
    /// 免费版提醒上限
    static let freeReminderLimit = 3
    /// 免费版历史记录窗口（天）
    static let freeHistoryDays = 90

    private let context: ModelContext
    private let clock: Clock
    private(set) var entitlements: [Entitlement] = []

    init(context: ModelContext, clock: Clock = SystemClock()) {
        self.context = context
        self.clock = clock
        refresh()
    }

    // MARK: - 判定

    /// 是否 Pro：任一有效权益
    var isPro: Bool {
        entitlements.contains { $0.isActive(at: clock.now) }
    }

    var petLimit: Int {
        isPro ? Self.proPetLimit : Self.freePetLimit
    }

    /// 提醒上限，nil 表示无限
    var reminderLimit: Int? {
        isPro ? nil : Self.freeReminderLimit
    }

    /// 历史记录窗口（天），nil 表示无限
    var historyWindowDays: Int? {
        isPro ? nil : Self.freeHistoryDays
    }

    func canAddPet(currentCount: Int) -> Bool {
        currentCount < petLimit
    }

    func canEnableReminder(currentEnabled: Int) -> Bool {
        guard let reminderLimit else { return true }
        return currentEnabled < reminderLimit
    }

    /// 免费用户超出历史窗口的日期是否锁定
    func isLocked(date: Date, now: Date? = nil) -> Bool {
        guard let days = historyWindowDays else { return false }
        let reference = now ?? clock.now
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: reference) else {
            return false
        }
        return date < cutoff
    }

    // MARK: - 写入

    /// 应用一次购买事件：撤销即失效，否则按产品 upsert 并刷新
    func apply(_ event: PurchaseEvent) {
        if event.revokedAt != nil {
            deactivate(productID: event.productID)
            return
        }

        let kind: EntitlementKind = event.expiresAt == nil ? .lifetime : .subscription
        let productID = event.productID
        let descriptor = FetchDescriptor<Entitlement>(
            predicate: #Predicate { $0.productID == productID }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.kind = kind
            existing.purchasedAt = event.purchasedAt
            existing.expiresAt = event.expiresAt
            existing.isActive = true
        } else {
            context.insert(Entitlement(
                productID: event.productID,
                kind: kind,
                purchasedAt: event.purchasedAt,
                expiresAt: event.expiresAt,
                isActive: true
            ))
        }
        save()
        refresh()
    }

    /// 恢复购买：批量应用
    func apply(events: [PurchaseEvent]) {
        for event in events {
            apply(event)
        }
    }

    private func deactivate(productID: String) {
        let id = productID
        let descriptor = FetchDescriptor<Entitlement>(
            predicate: #Predicate { $0.productID == id }
        )
        for item in (try? context.fetch(descriptor)) ?? [] {
            item.isActive = false
        }
        save()
        refresh()
    }

    /// 重新加载并把已过期的权益标记为失效
    func refresh() {
        let all = (try? context.fetch(FetchDescriptor<Entitlement>())) ?? []
        var changed = false
        for item in all where item.isActive && !item.isActive(at: clock.now) {
            item.isActive = false
            changed = true
        }
        if changed {
            save()
        }
        entitlements = all
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // 权益本地存储失败不阻断界面，下次刷新会重试
        }
    }
}
