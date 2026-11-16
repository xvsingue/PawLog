//
//  PawLogConfig.swift
//  PawLog
//
//  仓库级开关。上架版打开 isProEnabled；开源预览版默认关闭，所有 Pro
//  权益对所有用户解锁，订阅入口隐藏。StoreKit 代码与测试保留，方便上架时启用。
//

import Foundation

enum PawLogConfig {
    /// 是否启用订阅与免费限制。
    /// - false（默认，当前开源预览版）：所有用户视作 Pro，PetListView / ReminderListView / TimelineView
    ///   的 Paywall 触发点不会激活；StoreKit 代码与自动化测试仍然编译并通过。
    /// - true（上架版）：恢复 1 宠 / 3 提醒 / 90 天历史的免费限额，Paywall 在触发点弹出。
    static let isProEnabled: Bool = false
}
