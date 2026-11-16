//
//  ReminderListViewModel.swift
//  PawLog
//
//  提醒列表状态：即将到期 / 已过期两组，剩余天数，开关与完成操作。
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class ReminderListViewModel: ObservableObject {
    @Published private(set) var upcoming: [Reminder] = []
    @Published private(set) var overdue: [Reminder] = []

    private let pet: Pet
    private let service: ReminderService

    init(pet: Pet, service: ReminderService) {
        self.pet = pet
        self.service = service
    }

    /// 重新加载分组
    func reload() {
        let groups = service.fetchReminders(for: pet)
        upcoming = groups.upcoming
        overdue = groups.overdue
    }

    /// 距到期天数
    func daysRemaining(for reminder: Reminder) -> Int {
        service.daysRemaining(for: reminder)
    }

    /// 切换提醒开关
    func setEnabled(_ reminder: Reminder, enabled: Bool) {
        Task {
            try? await service.setEnabled(reminder, enabled: enabled)
            await MainActor.run { self.reload() }
        }
    }

    /// 标记完成
    func markDone(_ reminder: Reminder) {
        Task {
            try? await service.markDone(reminder)
            await MainActor.run { self.reload() }
        }
    }
}
