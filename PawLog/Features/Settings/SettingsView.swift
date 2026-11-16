//
//  SettingsView.swift
//  PawLog
//
//  设置：单位、语言、通知说明、导出摘要、清空数据、关于。
//

import SwiftUI
import SwiftData

/// 语言偏好。v1 仅支持跟随系统 / 简体中文，English 留到 v1.1。
enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case zhHans

    static let storageKey = "settings.language"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system: "settings.language.system"
        case .zhHans: "settings.language.zhHans"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.sortIndex) private var pets: [Pet]

    @AppStorage(WeightFormatter.storageKey) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(LanguagePreference.storageKey) private var languageRaw = LanguagePreference.system.rawValue

    @State private var showingPetPicker = false
    @State private var selectedPet: Pet?
    @State private var showingSummary = false
    @State private var showingClearConfirm = false
    @State private var showingTypedConfirm = false
    @State private var deleteText = ""
    @State private var errorMessage: String?

    private var unit: Binding<WeightUnit> {
        Binding(
            get: { WeightUnit(rawValue: unitRaw) ?? .kg },
            set: { newValue in
                unitRaw = newValue.rawValue
                WeightFormatter.setUnit(newValue)
            }
        )
    }

    private var language: Binding<LanguagePreference> {
        Binding(
            get: { LanguagePreference(rawValue: languageRaw) ?? .system },
            set: { languageRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                unitSection
                languageSection
                notificationSection
                exportSection
                BackupSettingsSection()
                dataSection
                aboutSection
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .confirmationDialog(
                String(localized: "settings.export.pickPet"),
                isPresented: $showingPetPicker,
                titleVisibility: .visible
            ) {
                ForEach(pets) { pet in
                    Button(pet.name) {
                        selectedPet = pet
                        showingSummary = true
                    }
                }
            }
            .sheet(isPresented: $showingSummary) {
                if let selectedPet {
                    SummaryView(pet: selectedPet)
                }
            }
            .alert(String(localized: "settings.data.clear.title"), isPresented: $showingClearConfirm) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "settings.data.clear.continue"), role: .destructive) {
                    deleteText = ""
                    showingTypedConfirm = true
                }
            } message: {
                Text(String(localized: "settings.data.clear.body"))
            }
            .alert(String(localized: "settings.data.clear.confirmTitle"), isPresented: $showingTypedConfirm) {
                TextField(String(localized: "settings.data.clear.hint"), text: $deleteText)
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "settings.data.clear.confirm"), role: .destructive) {
                    clearAllData()
                }
                .disabled(deleteText != String(localized: "settings.data.clear.confirm"))
            } message: {
                Text(String(localized: "settings.data.clear.confirmBody"))
            }
            .alert(String(localized: "settings.data.clear.failed"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            }
        }
    }

    // MARK: - 分组

    private var unitSection: some View {
        Section(String(localized: "settings.unit.header")) {
            Picker(String(localized: "settings.unit.header"), selection: unit) {
                ForEach(WeightUnit.allCases) { item in
                    Text(String(localized: String.LocalizationValue(item.titleKey))).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(String(localized: "settings.language.header"), selection: language) {
                ForEach(LanguagePreference.allCases) { item in
                    Text(String(localized: String.LocalizationValue(item.titleKey))).tag(item)
                }
            }
            .pickerStyle(.inline)

            // English 置灰，标注 v1.1 支持
            HStack {
                Text(String(localized: "settings.language.en"))
                Spacer()
                Text(String(localized: "settings.language.comingSoon"))
                    .font(Theme.Typography.caption)
            }
            .foregroundStyle(Theme.Palette.textTertiary)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)

            Text(String(localized: "settings.language.v1Hint"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        } header: {
            Text(String(localized: "settings.language.header"))
        }
    }

    private var notificationSection: some View {
        Section(String(localized: "settings.notification.header")) {
            Text(String(localized: "settings.notification.quietHours"))
            Text(String(localized: "settings.notification.overdueSummary"))
        }
    }

    private var exportSection: some View {
        Section(String(localized: "settings.export.header")) {
            Button(String(localized: "settings.export.action")) {
                showingPetPicker = true
            }
            .disabled(pets.isEmpty)
            if pets.isEmpty {
                Text(String(localized: "settings.export.empty"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var dataSection: some View {
        Section(String(localized: "settings.data.header")) {
            Button(String(localized: "settings.data.clear"), role: .destructive) {
                showingClearConfirm = true
            }
            .disabled(pets.isEmpty)
        }
    }

    private var aboutSection: some View {
        Section(String(localized: "settings.about.header")) {
            NavigationLink(String(localized: "settings.about.title")) {
                AboutView()
            }
        }
    }

    // MARK: - 操作

    private func clearAllData() {
        Task {
            do {
                try await DataResetService(context: modelContext).clearAllData()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("SettingsView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
        configurations: config
    )
    return SettingsView()
        .modelContainer(container)
}
