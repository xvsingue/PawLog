//
//  RecordDetailView.swift
//  PawLog
//
//  记录详情：按类型展示字段，可编辑、可删除（二次确认）。删除后不残留 WeightEntry。
//

import SwiftUI
import SwiftData

struct RecordDetailView: View {
    let record: Record
    let service: RecordService
    let reminderService: ReminderService?

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(record.title)
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(record.occurredAt.formatted(.dateTime.year().month().day()))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            fieldsSection

            if let note = record.note, !note.isEmpty {
                Section(String(localized: "record.section.note")) {
                    Text(note)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }

            Section {
                Button(String(localized: "record.action.delete"), role: .destructive) {
                    showingDeleteConfirm = true
                }
            }
        }
        .navigationTitle(String(localized: String.LocalizationValue(record.type.titleKey)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "common.edit")) {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let pet = record.pet {
                QuickRecordSheet(pet: pet, service: service, reminderService: reminderService, editing: record)
            }
        }
        .confirmationDialog(
            String(localized: "record.delete.confirm.title"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "record.delete.confirm.action"), role: .destructive) {
                deleteRecord()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("record.delete.confirm.message")
        }
        .alert(String(localized: "record.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let message = errorMessage { Text(message) }
        }
    }

    // MARK: - 字段

    @ViewBuilder
    private var fieldsSection: some View {
        switch record.type {
        case .vaccine:
            if let p = record.payload(VaccinePayload.self) {
                Section(String(localized: "record.type.vaccine")) {
                    row("record.field.vaccineName", p.vaccineName)
                    row("record.field.hospital", p.hospital)
                    row("record.field.batchNumber", p.batchNumber)
                    row("record.field.nextDate", p.nextDate?.formatted(.dateTime.year().month().day()))
                    row("record.field.adverseReaction", p.adverseReaction)
                }
            }
        case .deworming:
            if let p = record.payload(DewormingPayload.self) {
                Section(String(localized: "record.type.deworming")) {
                    row("record.field.scope", p.scope.localizedTitle)
                    row("record.field.drugName", p.drugName)
                    row("record.field.nextDate", p.nextDate?.formatted(.dateTime.year().month().day()))
                }
            }
        case .medication:
            if let p = record.payload(MedicationPayload.self) {
                Section(String(localized: "record.type.medication")) {
                    row("record.field.drugName", p.drugName)
                    row("record.field.dosage", p.dosage)
                    row("record.field.frequency", p.frequency)
                    row("record.field.route", p.route)
                    row("record.field.startDate", p.startDate?.formatted(.dateTime.year().month().day()))
                    row("record.field.endDate", p.endDate?.formatted(.dateTime.year().month().day()))
                }
            }
        case .visit:
            if let p = record.payload(VisitPayload.self) {
                Section(String(localized: "record.type.visit")) {
                    row("record.field.hospital", p.hospital)
                    row("record.field.doctor", p.doctor)
                    row("record.field.chiefComplaint", p.chiefComplaint)
                    row("record.field.diagnosis", p.diagnosis)
                    row("record.field.treatment", p.treatment)
                    row("record.field.cost", p.cost.map { String($0) })
                    row("record.field.followUpDate", p.followUpDate?.formatted(.dateTime.year().month().day()))
                }
            }
        case .symptom:
            if let p = record.payload(SymptomPayload.self) {
                Section(String(localized: "record.type.symptom")) {
                    row("record.field.symptomType", p.symptomType.localizedTitle)
                    row("record.field.severity", String(p.severity))
                    row("record.field.duration", p.duration)
                }
            }
        case .weight:
            if let p = record.payload(WeightPayload.self) {
                Section(String(localized: "record.type.weight")) {
                    row("record.field.weightKg", WeightFormatter.string(p.weightKg))
                    row("record.field.bcs", p.bcs.map { String($0) })
                }
            }
        case .daily:
            if let p = record.payload(DailyPayload.self) {
                Section(String(localized: "record.type.daily")) {
                    row("record.field.foodAmount", p.foodAmount)
                    row("record.field.water", p.water)
                    row("record.field.excretion", p.excretion)
                    row("record.field.exercise", p.exercise)
                    row("record.field.mood", p.mood)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ labelKey: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(String(localized: String.LocalizationValue(labelKey)))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text(value)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - 删除

    private func deleteRecord() {
        do {
            // RecordService.delete 会一并删除派生提醒并撤销通知
            try service.delete(record)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
