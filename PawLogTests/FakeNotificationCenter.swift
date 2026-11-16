//
//  FakeNotificationCenter.swift
//  PawLogTests
//
//  通知中心假实现：内存存储 pending 请求，供 NotificationService / ReminderService 测试。
//

import Foundation
import UserNotifications
@testable import PawLog

final class FakeNotificationCenter: NotificationCenterProtocol {
    private(set) var requests: [String: UNNotificationRequest] = [:]
    var authorizationGranted = true
    var addError: Error?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        requests[request.identifier] = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers {
            requests.removeValue(forKey: id)
        }
    }

    func getPendingNotificationRequests() async -> [UNNotificationRequest] {
        Array(requests.values)
    }

    /// 便捷：某提醒的 pending 数量
    func pendingCount(for reminderID: UUID) -> Int {
        let ids = Set(NotificationService.leadDays.map { "\(reminderID.uuidString)-\($0)" })
        return requests.keys.filter { ids.contains($0) }.count
    }
}
