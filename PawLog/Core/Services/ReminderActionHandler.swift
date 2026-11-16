//
//  ReminderActionHandler.swift
//  PawLog
//
//  通知动作回调：标记完成 / 稍后提醒，写回提醒数据并重排通知。
//

import Foundation
import SwiftData

/// 提醒通知动作
enum ReminderNotificationAction: String {
    case done = "REMINDER_DONE"
    case snooze = "REMINDER_SNOOZE"

    init?(identifier: String) {
        self.init(rawValue: identifier)
    }
}

/// 通知动作处理器
@MainActor
enum ReminderActionHandler {
    /// 稍后提醒默认延后天数
    static let snoozeDays = 1

    /// 按动作处理指定提醒
    static func perform(
        _ action: ReminderNotificationAction,
        reminderID: UUID,
        context: ModelContext,
        notificationService: NotificationService = NotificationService(),
        calendar: Calendar = .current,
        clock: Clock = SystemClock()
    ) async {
        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.id == reminderID }
        )
        guard let reminder = (try? context.fetch(descriptor))?.first else { return }
        let service = ReminderService(
            context: context,
            notificationService: notificationService,
            calendar: calendar,
            clock: clock
        )

        switch action {
        case .done:
            try? await service.markDone(reminder)
        case .snooze:
            await service.snooze(reminder, days: Self.snoozeDays)
        }
    }
}
