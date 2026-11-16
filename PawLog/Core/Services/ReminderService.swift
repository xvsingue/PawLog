//
//  ReminderService.swift
//  PawLog
//
//  提醒数据服务：从记录派生、标记完成（按重复规则推下次）、开关、查询、启动对账。
//

import Foundation
import SwiftData
import OSLog

/// 提醒服务
@MainActor
final class ReminderService {
    private let context: ModelContext
    private let notificationService: NotificationService
    private let calendar: Calendar
    private let clock: Clock
    /// 免费提醒上限（nil 表示不限）；仅影响通知排期，不删数据、不改开关
    private let reminderLimit: () -> Int?
    private let logger = Logger(subsystem: "com.Lennox.PawLog", category: "ReminderService")

    init(
        context: ModelContext,
        notificationService: NotificationService,
        calendar: Calendar = .current,
        clock: Clock = SystemClock(),
        reminderLimit: @escaping () -> Int? = { nil }
    ) {
        self.context = context
        self.notificationService = notificationService
        self.calendar = calendar
        self.clock = clock
        self.reminderLimit = reminderLimit
    }

    // MARK: - 权限

    /// 首次保存记录后申请通知权限，已申请过则跳过
    func requestAuthorizationIfNeeded() async {
        await notificationService.requestAuthorizationOnce()
    }

    // MARK: - 派生

    /// 从记录派生提醒。仅疫苗/驱虫/用药/就诊且有下次日期时生成。
    /// 同一 sourceRecordID 只保留一条（upsert），并同步排期通知。
    @discardableResult
    func deriveReminder(from record: Record) async -> Reminder? {
        guard let reminder = try? upsertDerivedReminder(for: record) else { return nil }
        await reschedule(reminder)
        return reminder
    }

    /// 同步 upsert 派生提醒的数据（不排期）。无下次日期时返回 nil。
    @discardableResult
    func upsertDerivedReminder(for record: Record) throws -> Reminder? {
        guard let (kind, dueAt) = Self.nextDateAndKind(for: record) else { return nil }

        let existing = record.pet?.reminders.first { $0.sourceRecordID == record.id }
        let reminder: Reminder
        if let existing {
            existing.kind = kind
            existing.dueAt = dueAt
            existing.enabled = true
            reminder = existing
        } else {
            reminder = Reminder(
                pet: record.pet,
                kind: kind,
                sourceRecordID: record.id,
                dueAt: dueAt,
                repeatRule: .none,
                enabled: true
            )
            context.insert(reminder)
        }
        try context.save()
        return reminder
    }

    /// 重新排期某提醒的全部通知：先撤销再按当前 dueAt 排期。
    /// 免费用户只有 dueAt 最近的若干条能排通知，其余撤销待发但不改动提醒数据。
    func reschedule(_ reminder: Reminder) async {
        if let limit = reminderLimit() {
            let enabled = ((try? context.fetch(FetchDescriptor<Reminder>())) ?? [])
                .filter(\.enabled)
                .sorted { $0.dueAt < $1.dueAt }
            let eligible = Set(enabled.prefix(limit).map(\.id))
            for item in enabled where !eligible.contains(item.id) {
                notificationService.cancel(for: item.id)
            }
            guard eligible.contains(reminder.id) else { return }
        }
        await notificationService.cancel(for: reminder.id)
        await notificationService.schedule(for: reminder)
    }

    /// 从记录载荷中提取下次日期与提醒类型
    static func nextDateAndKind(for record: Record) -> (ReminderKind, Date)? {
        switch record.type {
        case .vaccine:
            guard let date = record.payload(VaccinePayload.self)?.nextDate else { return nil }
            return (.vaccine, date)
        case .deworming:
            guard let date = record.payload(DewormingPayload.self)?.nextDate else { return nil }
            return (.deworming, date)
        case .medication:
            // 用药取疗程结束日
            guard let date = record.payload(MedicationPayload.self)?.endDate else { return nil }
            return (.medication, date)
        case .visit:
            guard let date = record.payload(VisitPayload.self)?.followUpDate else { return nil }
            return (.visit, date)
        default:
            return nil
        }
    }

    // MARK: - 完成

    /// 标记完成：更新 lastDoneAt，按 repeatRule 推下次 dueAt 并重新排期。
    /// 无重复规则时关闭提醒（视为一次性完成）。
    func markDone(_ reminder: Reminder) async throws {
        let now = clock.now
        reminder.lastDoneAt = now
        await notificationService.cancel(for: reminder.id)

        if let next = nextDueDate(from: now, rule: reminder.repeatRule) {
            reminder.dueAt = next
            try context.save()
            if reminder.enabled {
                await notificationService.schedule(for: reminder)
            }
        } else {
            reminder.enabled = false
            try context.save()
        }
    }

    /// 按重复规则计算下一次到期日
    private func nextDueDate(from date: Date, rule: RepeatRule) -> Date? {
        switch rule {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }

    // MARK: - 开关

    /// 切换提醒开关。关闭则撤销该提醒全部待发通知。
    func setEnabled(_ reminder: Reminder, enabled: Bool) async throws {
        reminder.enabled = enabled
        try context.save()
        if enabled {
            await reschedule(reminder)
        } else {
            await notificationService.cancel(for: reminder.id)
        }
    }

    // MARK: - 查询

    /// 分组查询：即将到期 / 已过期（均只含启用的提醒）
    func fetchReminders(for pet: Pet) -> (upcoming: [Reminder], overdue: [Reminder]) {
        let startOfToday = calendar.startOfDay(for: clock.now)
        let enabled = pet.reminders.filter { $0.enabled }
        let upcoming = enabled
            .filter { $0.dueAt >= startOfToday }
            .sorted { $0.dueAt < $1.dueAt }
        let overdue = enabled
            .filter { $0.dueAt < startOfToday }
            .sorted { $0.dueAt > $1.dueAt }
        return (upcoming, overdue)
    }

    /// 距到期天数（今天=0，已过为负）
    func daysRemaining(for reminder: Reminder) -> Int {
        let startOfToday = calendar.startOfDay(for: clock.now)
        let startOfDue = calendar.startOfDay(for: reminder.dueAt)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0
    }

    // MARK: - 对账

    /// 启动对账：对全部提醒执行通知对账（补缺失、清过期），并刷新逾期每日汇总。幂等。
    func reconcileAll() async {
        let descriptor = FetchDescriptor<Reminder>()
        let all = (try? context.fetch(descriptor)) ?? []
        let eligible: [Reminder]
        if let limit = reminderLimit() {
            eligible = all.filter(\.enabled)
                .sorted { $0.dueAt < $1.dueAt }
                .prefix(limit)
                .map { $0 }
        } else {
            eligible = all
        }
        await notificationService.reconcile(reminders: eligible)

        // 逾期（到期日早于今天）且仍启用的提醒，每天最多推 1 条汇总
        let overdueCount = all.filter { $0.enabled && daysRemaining(for: $0) < 0 }.count
        await notificationService.scheduleOverdueSummary(overdueCount: overdueCount)
    }

    /// 稍后提醒：延后若干天再推一次
    func snooze(_ reminder: Reminder, days: Int = 1) async {
        await notificationService.snooze(for: reminder, days: days)
    }

    // MARK: - 删除

    /// 删除某记录派生的提醒并撤销其通知（同步，供记录删除时调用）
    func deleteDerivedReminders(for record: Record) {
        let reminders = record.pet?.reminders.filter { $0.sourceRecordID == record.id } ?? []
        guard !reminders.isEmpty else { return }
        for reminder in reminders {
            notificationService.cancel(for: reminder.id)
            context.delete(reminder)
        }
        do {
            try context.save()
        } catch {
            logger.error("删除记录关联提醒失败：record=\(record.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
