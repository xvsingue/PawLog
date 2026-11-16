//
//  NotificationService.swift
//  PawLog
//
//  本地通知服务：申请权限、按 30/7/1 天偏移排期、撤销、启动对账。
//  通知 id = reminderID + 偏移天数，保证唯一且可单独撤销。
//

import Foundation
import OSLog
import UserNotifications

/// 通知中心协议，便于测试时用假实现替换 UNUserNotificationCenter
protocol NotificationCenterProtocol: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func getPendingNotificationRequests() async -> [UNNotificationRequest]
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

/// UNUserNotificationCenter 适配器
final class UNUserNotificationCenterAdapter: NotificationCenterProtocol {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func getPendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
}

/// 本地通知服务
final class NotificationService {
    /// 每条提醒在到期前推送的偏移天数（大→小）
    static let leadDays: [Int] = [30, 7, 1]

    /// 提醒通知分类与动作标识
    static let categoryIdentifier = "REMINDER"
    static let actionDone = "REMINDER_DONE"
    static let actionSnooze = "REMINDER_SNOOZE"
    /// 通知内容里携带提醒 id 的 key
    static let reminderIDKey = "reminderID"

    /// 逾期汇总通知 id 前缀
    static let overdueSummaryPrefix = "overdue-summary-"
    /// 逾期汇总提前排期天数
    static let overdueSummaryDays = 7
    /// 逾期汇总推送时刻（每天 09:00）
    static let overdueSummaryHour = 9

    private let center: NotificationCenterProtocol
    private let calendar: Calendar
    private let clock: Clock
    private let logger = Logger(subsystem: "com.Lennox.PawLog", category: "NotificationService")

    init(
        center: NotificationCenterProtocol = UNUserNotificationCenterAdapter(),
        calendar: Calendar = .current,
        clock: Clock = SystemClock()
    ) {
        self.center = center
        self.calendar = calendar
        self.clock = clock
    }

    // MARK: - 权限

    /// 是否已发起过权限申请（UserDefaults 持久化，跨进程只申请一次）
    private static let authorizationRequestedKey = "notification.authorizationRequested"

    /// 申请通知权限
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("通知权限申请失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 首次保存记录后申请权限；已申请过则跳过（PRD 5.4）
    @discardableResult
    func requestAuthorizationOnce() async -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.authorizationRequestedKey) else { return false }
        defaults.set(true, forKey: Self.authorizationRequestedKey)
        return await requestAuthorization()
    }

    // MARK: - id 规则

    /// 通知 id：reminderID 与偏移天数拼接，保证唯一可撤销
    func notificationID(reminderID: UUID, offsetDays: Int) -> String {
        "\(reminderID.uuidString)-\(offsetDays)"
    }

    // MARK: - 分类

    /// 注册提醒通知分类：长按可「标记完成 / 稍后提醒」
    func registerCategories() {
        let done = UNNotificationAction(
            identifier: Self.actionDone,
            title: String(localized: "notification.action.done"),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.actionSnooze,
            title: String(localized: "notification.action.snooze"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - 排期

    /// 为某条提醒排期全部偏移的通知。已过期的偏移不排。
    func schedule(for reminder: Reminder) async {
        let now = clock.now
        for offset in Self.leadDays {
            await scheduleSingle(reminder: reminder, offsetDays: offset, now: now)
        }
    }

    /// 排期单个偏移的通知
    private func scheduleSingle(reminder: Reminder, offsetDays: Int, now: Date) async {
        guard let fireDate = fireDate(for: reminder, offsetDays: offsetDays),
              fireDate > now else {
            // 偏移时间已过，不排
            return
        }
        let id = notificationID(reminderID: reminder.id, offsetDays: offsetDays)
        let content = UNMutableNotificationContent()
        content.title = reminder.notificationTitle
        content.body = reminder.notificationBody(offsetDays: offsetDays)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.reminderIDKey: reminder.id.uuidString]
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            logger.error("通知排期失败：id=\(id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 触发时间

    /// 某提醒某偏移的实际触发时间（已按静默时段顺延）
    private func fireDate(for reminder: Reminder, offsetDays: Int) -> Date? {
        guard let raw = calendar.date(byAdding: .day, value: -offsetDays, to: reminder.dueAt) else {
            return nil
        }
        return Self.adjustedFireDate(raw, calendar: calendar)
    }

    /// 22:00–08:00 静默：落在该区间的触发时间顺延到当日或次日 08:00
    static func adjustedFireDate(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= 22 || hour < 8 else { return date }

        let day = hour >= 22
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            : calendar.startOfDay(for: date)
        guard let day else { return date }
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? date
    }

    // MARK: - 撤销

    /// 撤销某条提醒的全部待发通知
    func cancel(for reminderID: UUID) {
        let ids = Self.leadDays.map { notificationID(reminderID: reminderID, offsetDays: $0) }
            + [snoozeID(reminderID: reminderID)]
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 撤销全部待发通知
    func cancelAll() async {
        let pending = await center.getPendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
    }

    // MARK: - 稍后提醒

    /// 稍后提醒通知 id
    func snoozeID(reminderID: UUID) -> String {
        "\(reminderID.uuidString)-snooze"
    }

    /// 延后若干天再提醒一次（同样遵守静默时段）
    func snooze(for reminder: Reminder, days: Int) async {
        guard reminder.enabled,
              let raw = calendar.date(byAdding: .day, value: days, to: clock.now) else { return }
        let fireDate = Self.adjustedFireDate(raw, calendar: calendar)
        guard fireDate > clock.now else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.notificationTitle
        content.body = String(localized: "notification.reminder.snoozeBody")
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.reminderIDKey: reminder.id.uuidString]

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: snoozeID(reminderID: reminder.id),
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            logger.error("稍后提醒排期失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 逾期汇总

    /// 逾期汇总通知 id：按日唯一，保证每天最多 1 条
    func overdueSummaryID(for date: Date) -> String {
        Self.overdueSummaryPrefix + date.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
    }

    /// 为存在逾期提醒的日子排期每日汇总（每天 09:00，最多 1 条）。幂等。
    func scheduleOverdueSummary(overdueCount: Int) async {
        let pending = await center.getPendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(Self.overdueSummaryPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        guard overdueCount > 0 else { return }

        for dayOffset in 0..<Self.overdueSummaryDays {
            guard let day = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: calendar.startOfDay(for: clock.now)
            ), let raw = calendar.date(bySettingHour: Self.overdueSummaryHour, minute: 0, second: 0, of: day) else {
                continue
            }
            // 与静默时段规则共用：09:00 本身不在静默区间，调整后保持不变
            let fireDate = Self.adjustedFireDate(raw, calendar: calendar)
            guard fireDate > clock.now else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.overdue.title")
            content.body = String(localized: "notification.overdue.body \(overdueCount)")
            content.sound = .default

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: overdueSummaryID(for: day),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("逾期汇总排期失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - 对账

    /// 启动对账：补齐缺失通知、清理已过期/多余通知。幂等。
    func reconcile(reminders: [Reminder]) async {
        let now = clock.now
        // 1. 计算当前应该存在的通知 id 集合
        var expectedIDs = Set<String>()
        for reminder in reminders where reminder.enabled {
            for offset in Self.leadDays {
                guard let fireDate = fireDate(for: reminder, offsetDays: offset),
                      fireDate > now else { continue }
                expectedIDs.insert(notificationID(reminderID: reminder.id, offsetDays: offset))
            }
        }

        // 2. 当前 pending
        let pending = await center.getPendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))

        // 3. 清理多余（已过期或不属于任何启用提醒）；逾期汇总与稍后提醒各自维护
        let staleIDs = pendingIDs.subtracting(expectedIDs)
            .filter { !$0.hasPrefix(Self.overdueSummaryPrefix) && !$0.hasSuffix("-snooze") }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(staleIDs))
        }

        // 4. 补齐缺失
        for reminder in reminders where reminder.enabled {
            for offset in Self.leadDays {
                let id = notificationID(reminderID: reminder.id, offsetDays: offset)
                guard expectedIDs.contains(id), !pendingIDs.contains(id) else { continue }
                await scheduleSingle(reminder: reminder, offsetDays: offset, now: now)
            }
        }
    }

    // MARK: - 查询（测试用）

    /// 某条提醒当前 pending 的通知数
    func pendingCount(for reminderID: UUID) async -> Int {
        let ids = Set(Self.leadDays.map { notificationID(reminderID: reminderID, offsetDays: $0) })
        let pending = await center.getPendingNotificationRequests()
        return pending.filter { ids.contains($0.identifier) }.count
    }
}

// MARK: - 文案

extension Reminder {
    /// 通知标题：宠物名 · 提醒类型
    var notificationTitle: String {
        let petName = pet?.name ?? ""
        let kindKey = kind.notificationTitleKey
        if petName.isEmpty {
            return String(localized: String.LocalizationValue(kindKey))
        }
        return String(localized: "notification.reminder.title \(petName) \(String(localized: String.LocalizationValue(kindKey)))")
    }

    /// 通知正文：还有 N 天到期
    func notificationBody(offsetDays: Int) -> String {
        String(localized: "notification.reminder.body \(offsetDays)")
    }
}

extension ReminderKind {
    /// 通知标题中的类型文案 key
    var notificationTitleKey: String {
        switch self {
        case .vaccine: "notification.kind.vaccine"
        case .deworming: "notification.kind.deworming"
        case .medication: "notification.kind.medication"
        case .visit: "notification.kind.visit"
        case .custom: "notification.kind.custom"
        }
    }
}
