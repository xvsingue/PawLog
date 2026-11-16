//
//  StoreKitConfigurationTests.swift
//  PawLogTests
//
//  用 StoreKit Configuration 直连验证：商品一致、购买解锁、退款回落、恢复购买。
//

import XCTest
import StoreKit
import StoreKitTest
import SwiftData
@testable import PawLog

@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    private var session: SKTestSession!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: EntitlementService!

    override func setUpWithError() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configURL = repoRoot.appendingPathComponent("PawLog.storekit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path), "缺少 PawLog.storekit")

        session = try SKTestSession(contentsOf: configURL)
        session.disableDialogs = true
        session.clearTransactions()

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            configurations: config
        )
        context = container.mainContext
        service = EntitlementService(context: context)
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
        session = nil
        service = nil
        context = nil
        container = nil
    }

    /// productID 常量必须与 .storekit 配置一致
    func testProductIDsMatchConfiguration() async throws {
        let products = try await Product.products(for: StoreKitService.productIDs)
        XCTAssertEqual(
            Set(products.map(\.id)),
            Set(StoreKitService.productIDs),
            "代码中的 productID 与 .storekit 配置不一致"
        )
        XCTAssertEqual(products.count, 3)
    }

    /// 购买后 isPro 为真且限额放开
    func testPurchaseUnlocksPro() async throws {
        let transaction = try await session.buyProduct(identifier: StoreKitService.monthlyID)
        service.apply(StoreKitService.event(from: transaction))

        XCTAssertTrue(service.isPro)
        XCTAssertEqual(service.petLimit, EntitlementService.proPetLimit)
        XCTAssertNil(service.reminderLimit)
        XCTAssertNil(service.historyWindowDays)
    }

    /// 退款后回落免费态
    func testRefundFallsBackToFree() async throws {
        let purchased = try await session.buyProduct(identifier: StoreKitService.monthlyID)
        service.apply(StoreKitService.event(from: purchased))
        XCTAssertTrue(service.isPro)

        try session.refundTransaction(identifier: UInt(purchased.id))

        // 退款后 StoreKit 会投递撤销事件，这里按同类事件验证回落逻辑
        let refunded = try XCTUnwrap(
            session.allTransactions().first { $0.identifier == UInt(purchased.id) }
        )
        XCTAssertEqual(refunded.productIdentifier, StoreKitService.monthlyID)
        service.apply(PurchaseEvent(
            productID: purchased.productID,
            purchasedAt: purchased.purchaseDate,
            expiresAt: purchased.expirationDate,
            revokedAt: Date()
        ))
        XCTAssertFalse(service.isPro)
        XCTAssertEqual(service.petLimit, EntitlementService.freePetLimit)
    }

    /// 恢复购买：用 currentEntitlements 还原到新设备（新权益库）
    func testRestoreRebuildsPro() async throws {
        _ = try await session.buyProduct(identifier: StoreKitService.lifetimeID)

        let events = await currentEntitlementEvents()
        XCTAssertFalse(events.isEmpty, "当前权益应包含已购商品")

        let freshConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        let freshContainer = try ModelContainer(
            for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
            configurations: freshConfig
        )
        let restored = EntitlementService(context: freshContainer.mainContext)
        XCTAssertFalse(restored.isPro)

        restored.apply(events: events)
        XCTAssertTrue(restored.isPro, "恢复购买应还原 Pro")
    }

    // MARK: - 工具

    /// 购买后 currentEntitlements 由系统异步同步，最多等 3 秒
    private func currentEntitlementEvents(timeout: TimeInterval = 3) async -> [PurchaseEvent] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            var events: [PurchaseEvent] = []
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      transaction.revocationDate == nil else { continue }
                events.append(StoreKitService.event(from: transaction))
            }
            if !events.isEmpty { return events }
            try? await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        return []
    }
}
