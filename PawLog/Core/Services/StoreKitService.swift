//
//  StoreKitService.swift
//  PawLog
//
//  StoreKit 2：拉取商品、购买、恢复、处理延迟交易/退款。无服务端校验。
//

import Foundation
import StoreKit
import Observation
import os

@MainActor
@Observable
final class StoreKitService {
    static let monthlyID = "com.Lennox.PawLog.pro.monthly"
    static let yearlyID = "com.Lennox.PawLog.pro.yearly"
    static let lifetimeID = "com.Lennox.PawLog.pro.lifetime"
    static let productIDs = [monthlyID, yearlyID, lifetimeID]

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    /// Transaction.updates 回调（延迟交易、退款、撤销）
    var onEvent: (@MainActor (PurchaseEvent) -> Void)?

    private var updatesTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.pawlog.app", category: "StoreKit")

    /// 拉取三档商品
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            logger.error("加载商品失败：\(error.localizedDescription, privacy: .public)")
            products = []
        }
    }

    /// 购买，成功返回事件供上层写入权益
    func purchase(_ product: Product) async throws -> PurchaseEvent? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return nil }
            let event = Self.event(from: transaction)
            await transaction.finish()
            return event
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    /// 恢复购买：同步后用 currentEntitlements 还原
    func restore() async throws -> [PurchaseEvent] {
        try await AppStore.sync()
        var events: [PurchaseEvent] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            events.append(Self.event(from: transaction))
        }
        return events
    }

    /// 监听交易更新（只启动一次）
    func startObservingUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result else { continue }
                let event = Self.event(from: transaction)
                self.onEvent?(event)
                await transaction.finish()
            }
        }
    }

    nonisolated static func event(from transaction: Transaction) -> PurchaseEvent {
        PurchaseEvent(
            productID: transaction.productID,
            purchasedAt: transaction.purchaseDate,
            expiresAt: transaction.expirationDate,
            revokedAt: transaction.revocationDate
        )
    }
}
