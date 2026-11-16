//
//  QuickRecordSheet.swift
//  PawLog
//
//  快速记录 Sheet：先选类型，再填表单。默认值已就绪，尽量 3 次点击内保存。
//

import SwiftUI

struct QuickRecordSheet: View {
    let pet: Pet
    let service: RecordService
    let reminderService: ReminderService?
    var editing: Record?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: RecordType?

    init(pet: Pet, service: RecordService, reminderService: ReminderService? = nil, editing: Record? = nil) {
        self.pet = pet
        self.service = service
        self.reminderService = reminderService
        self.editing = editing
        _selectedType = State(initialValue: editing?.type)
    }

    #if DEBUG
    /// 仅截图用：跳过类型选择，直接进入指定类型的表单
    init(pet: Pet, service: RecordService, reminderService: ReminderService?, debugType: RecordType) {
        self.init(pet: pet, service: service, reminderService: reminderService, editing: nil)
        _selectedType = State(initialValue: debugType)
    }
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if let type = selectedType {
                    QuickRecordForm(
                        pet: pet,
                        service: service,
                        reminderService: reminderService,
                        type: type,
                        editing: editing,
                        onSaved: { dismiss() }
                    )
                } else {
                    typePicker
                }
            }
            .navigationTitle(String(localized: editing == nil ? "record.add.title" : "record.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedType != nil && editing == nil {
                        Button(String(localized: "common.back")) {
                            selectedType = nil
                        }
                    } else {
                        Button(String(localized: "common.cancel")) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var typePicker: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(RecordType.allCases, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: type.symbolName)
                                .font(.system(size: 24))
                                .foregroundStyle(type.tint)
                            Text(String(localized: String.LocalizationValue(type.titleKey)))
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .background(Theme.Palette.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record.type.\(type.rawValue)")
                }
            }
            .padding(Theme.Spacing.pageMargin)
        }
        .background(Theme.Palette.background)
    }
}

// MARK: - 表单

private struct QuickRecordForm: View {
    let type: RecordType
    let onSaved: () -> Void

    @StateObject private var viewModel: QuickRecordViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var showingWeightConfirm = false
    /// 超界体重经二次确认后置为 true，允许本次保存
    @State private var confirmedWeight = false
    @FocusState private var isFirstFieldFocused: Bool

    init(pet: Pet, service: RecordService, reminderService: ReminderService? = nil, type: RecordType, editing: Record?, onSaved: @escaping () -> Void) {
        self.type = type
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: QuickRecordViewModel(
            pet: pet,
            service: service,
            type: type,
            editing: editing,
            reminderService: reminderService
        ))
    }

    var body: some View {
        Form {
            Section(String(localized: "record.section.when")) {
                DatePicker(
                    String(localized: "record.field.date"),
                    selection: $viewModel.draft.occurredAt,
                    displayedComponents: .date
                )
            }

            typeFields

            Section(String(localized: "record.section.note")) {
                TextField(
                    String(localized: "record.field.note.placeholder"),
                    text: $viewModel.draft.note,
                    axis: .vertical
                )
                .lineLimit(3...6)
            }
        }
        .onAppear {
            if type.hasRequiredTextField {
                isFirstFieldFocused = true
            }
        }
        .navigationTitle(String(localized: String.LocalizationValue(type.titleKey)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "common.save")) {
                    save()
                }
                .disabled(!viewModel.isValid)
                .accessibilityIdentifier("record.save")
            }
        }
        .alert(String(localized: "record.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let message = errorMessage { Text(message) }
        }
        .alert(String(localized: "record.weight.confirm.title"), isPresented: $showingWeightConfirm) {
            Button(String(localized: "common.cancel"), role: .cancel) {
                confirmedWeight = false
            }
            Button(String(localized: "record.weight.confirm.ok")) {
                confirmedWeight = true
                save()
            }
        } message: {
            Text(String(localized: "record.weight.confirm.body"))
        }
    }

    @ViewBuilder
    private var typeFields: some View {
        switch type {
        case .vaccine:
            Section(String(localized: "record.type.vaccine")) {
                requiredField("record.field.vaccineName", text: $viewModel.draft.vaccineName)
                optionalField("record.field.hospital", text: $viewModel.draft.hospital)
                optionalField("record.field.batchNumber", text: $viewModel.draft.batchNumber)
                optionalDate("record.field.nextDate", isOn: $viewModel.draft.hasNextDate, date: $viewModel.draft.nextDate)
                optionalField("record.field.adverseReaction", text: $viewModel.draft.adverseReaction)
            }
        case .deworming:
            Section(String(localized: "record.type.deworming")) {
                Picker(String(localized: "record.field.scope"), selection: $viewModel.draft.dewormingScope) {
                    ForEach(DewormingScope.allCases, id: \.self) { scope in
                        Text(String(localized: String.LocalizationValue(scope.titleKey))).tag(scope)
                    }
                }
                optionalField("record.field.drugName", text: $viewModel.draft.drugName)
                optionalDate("record.field.nextDate", isOn: $viewModel.draft.hasNextDate, date: $viewModel.draft.nextDate)
            }
        case .medication:
            Section(String(localized: "record.type.medication")) {
                requiredField("record.field.drugName", text: $viewModel.draft.drugName)
                requiredField("record.field.dosage", text: $viewModel.draft.dosage)
                requiredField("record.field.frequency", text: $viewModel.draft.frequency)
                optionalField("record.field.route", text: $viewModel.draft.route)
                Toggle(String(localized: "record.field.medicationRange"), isOn: $viewModel.draft.hasMedicationRange)
                    .tint(Theme.Palette.primary)
                if viewModel.draft.hasMedicationRange {
                    DatePicker(String(localized: "record.field.startDate"), selection: $viewModel.draft.startDate, displayedComponents: .date)
                    DatePicker(String(localized: "record.field.endDate"), selection: $viewModel.draft.endDate, displayedComponents: .date)
                }
            }
        case .visit:
            Section(String(localized: "record.type.visit")) {
                requiredField("record.field.hospital", text: $viewModel.draft.hospital)
                optionalField("record.field.doctor", text: $viewModel.draft.doctor)
                optionalField("record.field.chiefComplaint", text: $viewModel.draft.chiefComplaint)
                optionalField("record.field.diagnosis", text: $viewModel.draft.diagnosis)
                optionalField("record.field.treatment", text: $viewModel.draft.treatment)
                optionalField("record.field.cost", text: $viewModel.draft.costText, decimal: true)
                optionalDate("record.field.followUpDate", isOn: $viewModel.draft.hasFollowUp, date: $viewModel.draft.followUpDate)
            }
        case .symptom:
            Section(String(localized: "record.type.symptom")) {
                Picker(String(localized: "record.field.symptomType"), selection: $viewModel.draft.symptomType) {
                    ForEach(SymptomType.allCases, id: \.self) { item in
                        Text(String(localized: String.LocalizationValue(item.titleKey))).tag(item)
                    }
                }
                Picker(String(localized: "record.field.severity"), selection: $viewModel.draft.severity) {
                    Text("record.severity.1").tag(1)
                    Text("record.severity.2").tag(2)
                    Text("record.severity.3").tag(3)
                }
                optionalField("record.field.duration", text: $viewModel.draft.duration)
            }
        case .weight:
            Section(String(localized: "record.type.weight")) {
                requiredField("record.field.weightKg", text: $viewModel.draft.weightText, decimal: true)
                if let kg = weightKilograms, kg > 0 {
                    Text(WeightFormatter.dualString(kg))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Toggle(String(localized: "record.field.hasBCS"), isOn: $viewModel.draft.hasBCS)
                    .tint(Theme.Palette.primary)
                if viewModel.draft.hasBCS {
                    Stepper(
                        String(localized: "record.field.bcs \(viewModel.draft.bcs)"),
                        value: $viewModel.draft.bcs,
                        in: 1...9
                    )
                }
            }
        case .daily:
            Section(String(localized: "record.type.daily")) {
                optionalField("record.field.foodAmount", text: $viewModel.draft.foodAmount)
                optionalField("record.field.water", text: $viewModel.draft.water)
                optionalField("record.field.excretion", text: $viewModel.draft.excretion)
                optionalField("record.field.exercise", text: $viewModel.draft.exercise)
                optionalField("record.field.mood", text: $viewModel.draft.mood)
            }
        }
    }

    // MARK: - 字段构造

    private func requiredField(_ labelKey: String, text: Binding<String>, decimal: Bool = false) -> some View {
        HStack {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .foregroundStyle(Theme.Palette.textPrimary)
            TextField(String(localized: "common.required"), text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(decimal ? .decimalPad : .default)
                .focused($isFirstFieldFocused)
        }
    }

    private func optionalField(_ labelKey: String, text: Binding<String>, decimal: Bool = false) -> some View {
        HStack {
            Text(String(localized: String.LocalizationValue(labelKey)))
                .foregroundStyle(Theme.Palette.textPrimary)
            TextField(String(localized: "common.optional"), text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(decimal ? .decimalPad : .default)
        }
    }

    private func optionalDate(_ labelKey: String, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        Group {
            Toggle(String(localized: String.LocalizationValue(labelKey)), isOn: isOn)
                .tint(Theme.Palette.primary)
            if isOn.wrappedValue {
                DatePicker(String(localized: String.LocalizationValue(labelKey)), selection: date, displayedComponents: .date)
            }
        }
    }

    private func save() {
        // 体重超出 0.2–120kg 先二次确认，确认后再保存
        if type == .weight, let kg = weightKilograms, !WeightFormatter.isWithinRange(kg), !confirmedWeight {
            showingWeightConfirm = true
            return
        }
        confirmedWeight = false
        do {
            try viewModel.save()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var weightKilograms: Double? {
        Double(viewModel.draft.weightText)
    }
}

extension RecordType {
    /// 是否有必填文本框（用于表单自动聚焦）
    var hasRequiredTextField: Bool {
        switch self {
        case .vaccine, .medication, .visit, .weight: return true
        case .deworming, .symptom, .daily: return false
        }
    }
}
