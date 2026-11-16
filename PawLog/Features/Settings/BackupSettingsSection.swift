//
//  BackupSettingsSection.swift
//  PawLog
//
//  设置页的备份分组：导出 JSON 备份、从文件恢复。
//  恢复前若本地已有数据，必须输入「覆盖」二次确认。
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var exportURL: URL?
    @State private var showingShare = false
    @State private var showingImporter = false
    @State private var pendingData: Data?
    @State private var existingRecordCount = 0
    @State private var overwriteText = ""
    @State private var showingOverwriteConfirm = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var service: BackupService { BackupService(context: modelContext) }

    var body: some View {
        Section {
            Button(String(localized: "settings.backup.export")) { export() }

            Button(String(localized: "settings.backup.restore")) { showingImporter = true }

            if let statusMessage {
                Text(statusMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        } header: {
            Text(String(localized: "settings.backup.header"))
        } footer: {
            Text(String(localized: "settings.backup.footer"))
        }
        .sheet(isPresented: $showingShare) {
            if let exportURL {
                BackupShareSheet(url: exportURL)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            String(localized: "settings.backup.restore.confirmTitle"),
            isPresented: $showingOverwriteConfirm
        ) {
            TextField(String(localized: "settings.backup.restore.hint"), text: $overwriteText)
            Button(String(localized: "common.cancel"), role: .cancel) { pendingData = nil }
            Button(String(localized: "settings.backup.restore.confirm"), role: .destructive) {
                if let pendingData { performImport(pendingData) }
            }
            .disabled(overwriteText != String(localized: "settings.backup.restore.confirm"))
        } message: {
            Text(String(localized: "settings.backup.restore.confirmBody \(existingRecordCount)"))
        }
        .alert(String(localized: "settings.backup.failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 导出

    private func export() {
        do {
            exportURL = try service.writeTemporaryBackup()
            statusMessage = nil
            showingShare = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 恢复

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            // 先完整校验，再决定是否弹覆盖确认
            _ = try service.decode(data)
            let existing = try service.existingCounts().records

            if existing > 0 {
                pendingData = data
                existingRecordCount = existing
                overwriteText = ""
                showingOverwriteConfirm = true
            } else {
                performImport(data)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport(_ data: Data) {
        Task {
            do {
                let counts = try await service.importBackup(data, overwriteConfirmed: true)
                statusMessage = String(localized: "settings.backup.restore.success \(counts.total)")
            } catch {
                errorMessage = error.localizedDescription
            }
            pendingData = nil
        }
    }
}

// MARK: - 分享

private struct BackupShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "doc.text")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.primary)

                Text(url.lastPathComponent)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text(String(localized: "settings.backup.share.hint"))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)

                ShareLink(item: url) {
                    Text(String(localized: "settings.backup.share.action"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.primary)
            }
            .padding(Theme.Spacing.xl)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("BackupSettingsSection") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
        configurations: config
    )
    return Form { BackupSettingsSection() }
        .modelContainer(container)
}
