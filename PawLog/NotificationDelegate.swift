//
//  NotificationDelegate.swift
//  PawLog
//
//  接收通知动作回调，转交 ReminderActionHandler。仅在启动时注册一次。
//

import Foundation
import SwiftData
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {
        super.init()
    }

    /// 前台也展示提醒，避免排期后无感知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// 长按通知选择「标记完成 / 稍后提醒」
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info[NotificationService.reminderIDKey] as? String,
              let reminderID = UUID(uuidString: raw),
              let action = ReminderNotificationAction(identifier: response.actionIdentifier) else {
            return
        }
        await ReminderActionHandler.perform(
            action,
            reminderID: reminderID,
            context: PawLogApp.sharedContainer.mainContext
        )
    }
}
