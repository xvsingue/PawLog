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
}

/// 本地通知服务
final class NotificationService {
    /// 每条提醒在到期前推送的偏移天数（大→小）
    static let leadDays: [Int] = [30, 7, 1]

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
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 撤销全部待发通知
    func cancelAll() async {
        let pending = await center.getPendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
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

        // 3. 清理多余（已过期或不属于任何启用提醒）
        let staleIDs = pendingIDs.subtracting(expectedIDs)
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
