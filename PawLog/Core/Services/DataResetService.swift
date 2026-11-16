//
//  DataResetService.swift
//  PawLog
//
//  清空全部数据：删除所有业务数据并撤销待发通知。
//  删除逻辑统一走 ModelCleanup，与备份恢复共用同一份实现。
//

import Foundation
import SwiftData

@MainActor
final class DataResetService {
    private let context: ModelContext
    private let notificationService: NotificationService

    init(context: ModelContext, notificationService: NotificationService = NotificationService()) {
        self.context = context
        self.notificationService = notificationService
    }

    /// 删除全部宠物及其级联数据，并撤销全部待发通知。
    /// 保留 Entitlement：清空数据不应抹掉已购买权益。
    func clearAllData() async throws {
        try ModelCleanup.deleteBusinessData(in: context)
        try context.save()
        await notificationService.cancelAll()
    }
}
