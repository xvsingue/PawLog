//
//  PaywallView.swift
//  PawLog
//
//  订阅页：价值主张、三档价格、恢复购买、条款与隐私。
//

import SwiftUI
import SwiftData
import StoreKit

/// 付费墙展示项：StoreKit 商品或 DEBUG 截图用的示例项
struct PaywallProduct: Identifiable {
    let id: String
    let title: String
    let price: String
    let period: String
    /// 示例项没有真实商品，不可购买
    let product: Product?
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementService.self) private var entitlements
    @Environment(StoreKitService.self) private var store

    /// 仅用于 DEBUG 截图预览，正式路径传空
    private let sampleProducts: [PaywallProduct]

    init(sampleProducts: [PaywallProduct] = []) {
        self.sampleProducts = sampleProducts
    }

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingPrivacy = false

    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    productList
                    restoreButton
                    legalLinks
                }
                .padding(Theme.Spacing.pageMargin)
            }
            .background(Theme.Palette.background)
            .navigationTitle(String(localized: "paywall.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .task { await store.loadProducts() }
            .sheet(isPresented: $showingPrivacy) {
                privacySheet
            }
            .alert(String(localized: "paywall.purchase.failed"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(String(localized: "paywall.value"))
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(String(localized: "paywall.note"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var displayProducts: [PaywallProduct] {
        guard store.products.isEmpty else {
            return store.products.map { product in
                PaywallProduct(
                    id: product.id,
                    title: product.displayName,
                    price: product.displayPrice,
                    period: periodText(for: product),
                    product: product
                )
            }
        }
        return sampleProducts
    }

    private var productList: some View {
        VStack(spacing: Theme.Spacing.md) {
            if displayProducts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
            } else {
                ForEach(displayProducts) { product in
                    productCard(product)
                }
            }
        }
    }

    private func productCard(_ product: PaywallProduct) -> some View {
        Button {
            if let real = product.product { buy(real) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(product.title)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(product.period)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Text(product.price)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Palette.primary)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(isWorking || product.product == nil)
    }

    private func periodText(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return String(localized: "paywall.period.lifetime")
        }
        switch period.unit {
        case .month:
            return String(localized: "paywall.period.monthly")
        case .year:
            return String(localized: "paywall.period.yearly")
        default:
            return String(localized: "paywall.period.other")
        }
    }

    private var restoreButton: some View {
        Button {
            restore()
        } label: {
            Text(String(localized: "paywall.restore"))
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isWorking)
    }

    private var legalLinks: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Link(String(localized: "paywall.terms"), destination: termsURL)
            Button(String(localized: "paywall.privacy")) { showingPrivacy = true }
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
    }

    private var privacySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(String(localized: "paywall.privacy.body"))
                        .font(Theme.Typography.callout)
                    Text(String(localized: "summary.disclaimer"))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(Theme.Spacing.pageMargin)
            }
            .navigationTitle(String(localized: "paywall.privacy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { showingPrivacy = false }
                }
            }
        }
    }

    // MARK: - 操作

    private func buy(_ product: Product) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                if let event = try await store.purchase(product) {
                    entitlements.apply(event)
                    if entitlements.isPro { dismiss() }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let events = try await store.restore()
                entitlements.apply(events: events)
                if entitlements.isPro { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("PaywallView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
        configurations: config
    )
    return PaywallView()
        .environment(EntitlementService(context: container.mainContext))
        .environment(StoreKitService())
}
