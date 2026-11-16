//
//  DataResetService.swift
//  PawLog
//
//  清空全部数据：删除所有模型并撤销待发通知。
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

    /// 删除全部宠物及其级联数据，并撤销全部待发通知
    func clearAllData() async throws {
        try context.delete(model: Record.self)
        try context.delete(model: WeightEntry.self)
        try context.delete(model: Reminder.self)
        try context.delete(model: Attachment.self)
        try context.delete(model: Entitlement.self)
        try context.delete(model: Pet.self)
        try context.save()
        await notificationService.cancelAll()
    }
}
