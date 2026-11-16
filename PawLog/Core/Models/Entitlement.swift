//
//  Entitlement.swift
//  PawLog
//
//  权益记录：本地持久化，不做服务端校验。
//

import Foundation
import SwiftData

/// 权益类型
enum EntitlementKind: String, Codable {
    case subscription
    case lifetime
}

@Model
final class Entitlement {
    var id: UUID
    var productID: String
    var kind: EntitlementKind
    var purchasedAt: Date
    var expiresAt: Date?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        productID: String,
        kind: EntitlementKind,
        purchasedAt: Date,
        expiresAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.productID = productID
        self.kind = kind
        self.purchasedAt = purchasedAt
        self.expiresAt = expiresAt
        self.isActive = isActive
    }

    /// 当前时刻是否有效
    func isActive(at date: Date) -> Bool {
        guard isActive else { return false }
        guard let expiresAt else { return true }
        return expiresAt > date
    }
}
