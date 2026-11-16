//
//  SummaryView.swift
//  PawLog
//
//  就诊摘要预览与分享：生成 PDF / 长图后通过 ShareLink 分享。
//

import SwiftUI
import SwiftData

struct SummaryView: View {
    let pet: Pet

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: SummarySnapshot?
    @State private var pdfURL: URL?
    @State private var imageURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.groupSpacing) {
                    previewCard
                    actions
                }
                .padding(Theme.Spacing.pageMargin)
            }
            .background(Theme.Palette.background)
            .navigationTitle(String(localized: "summary.view.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .task(priority: .userInitiated) { export() }
            .alert(
                String(localized: "summary.error.title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 预览

    private var previewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(pet.name)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Palette.textPrimary)

                if let snapshot {
                    Text(String(localized: "summary.preview.range \(snapshot.rangeDays) \(snapshot.records.count)"))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    if let change = snapshot.weightChange {
                        Text(String(localized: "summary.weight.summary \(change.startText) \(change.endText) \(change.changeText)"))
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                } else {
                    Text(String(localized: "summary.preview.preparing"))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Text(String(localized: "summary.disclaimer"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    // MARK: - 操作

    @ViewBuilder
    private var actions: some View {
        if let pdfURL, let imageURL {
            VStack(spacing: Theme.Spacing.md) {
                ShareLink(item: pdfURL) {
                    shareLabel("summary.share.pdf", isPrimary: true)
                }
                ShareLink(item: imageURL) {
                    shareLabel("summary.share.image", isPrimary: false)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
        }
    }

    private func shareLabel(_ key: String, isPrimary: Bool) -> some View {
        Text(String(localized: String.LocalizationValue(key)))
            .font(Theme.Typography.title3)
            .foregroundStyle(isPrimary ? .white : Theme.Palette.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isPrimary ? Theme.Palette.primary : Theme.Palette.fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
    }

    // MARK: - 导出

    private func export() {
        guard pdfURL == nil else { return }
        let service = SummaryPDFService()
        let built = SummarySnapshotBuilder.make(pet: pet)
        snapshot = built
        do {
            pdfURL = try service.writePDF(built, petName: pet.name)
            imageURL = try service.writeLongImage(built, petName: pet.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("SummaryView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
        configurations: config
    )
    let context = container.mainContext
    let pet = Pet(name: "咪咪", species: .cat, breed: "英短", chipID: "900123456789012")
    context.insert(pet)
    return SummaryView(pet: pet)
        .modelContainer(container)
}
