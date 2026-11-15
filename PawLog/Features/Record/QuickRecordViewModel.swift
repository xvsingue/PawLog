//
//  QuickRecordViewModel.swift
//  PawLog
//
//  快速记录表单状态与保存逻辑。日期默认今天，医院与药品默认上次使用值。
//

import Foundation
import Combine

/// 记录表单草稿
struct RecordDraft {
    var occurredAt = Date()
    var note = ""

    // 疫苗
    var vaccineName = ""
    var hospital = ""
    var batchNumber = ""
    var adverseReaction = ""
    var hasNextDate = false
    var nextDate = Date()

    // 驱虫
    var dewormingScope: DewormingScope = .both

    // 用药
    var drugName = ""
    var dosage = ""
    var frequency = ""
    var route = ""
    var hasMedicationRange = false
    var startDate = Date()
    var endDate = Date()

    // 就诊
    var doctor = ""
    var chiefComplaint = ""
    var diagnosis = ""
    var treatment = ""
    var costText = ""
    var hasFollowUp = false
    var followUpDate = Date()

    // 症状
    var symptomType: SymptomType = .vomit
    var severity = 1
    var duration = ""

    // 体重
    var weightText = ""
    var hasBCS = false
    var bcs = 5

    // 日常
    var foodAmount = ""
    var water = ""
    var excretion = ""
    var exercise = ""
    var mood = ""
}

@MainActor
final class QuickRecordViewModel: ObservableObject {
    let type: RecordType
    @Published var draft: RecordDraft
    @Published var errorMessage: String?

    private let service: RecordService
    private let pet: Pet
    private let editing: Record?

    var isEditing: Bool { editing != nil }

    /// 必填项是否齐全
    var isValid: Bool {
        switch type {
        case .vaccine:
            return !draft.vaccineName.trimmed.isEmpty
        case .deworming:
            return true
        case .medication:
            return !draft.drugName.trimmed.isEmpty
                && !draft.dosage.trimmed.isEmpty
                && !draft.frequency.trimmed.isEmpty
        case .visit:
            return !draft.hospital.trimmed.isEmpty
        case .symptom:
            return (1...3).contains(draft.severity)
        case .weight:
            guard let kg = Double(draft.weightText) else { return false }
            return kg > 0
        case .daily:
            return true
        }
    }

    init(pet: Pet, service: RecordService, type: RecordType, editing: Record? = nil) {
        self.pet = pet
        self.service = service
        self.type = type
        self.editing = editing

        var initial = RecordDraft()
        if let editing {
            initial.occurredAt = editing.occurredAt
            initial.note = editing.note ?? ""
            Self.fill(&initial, from: editing)
        } else {
            initial.hospital = service.lastHospital(for: pet) ?? ""
            initial.drugName = service.lastDrugName(for: pet) ?? ""
        }
        self.draft = initial
    }

    /// 保存。抛出验证错误由 View 提示。
    func save() throws {
        let payloadJSON = buildPayloadJSON()
        let weight: WeightInput? = type == .weight
            ? WeightInput(kg: Double(draft.weightText) ?? 0, bcs: draft.hasBCS ? draft.bcs : nil)
            : nil
        let note = draft.note.trimmed.isEmpty ? nil : draft.note

        if let editing {
            try service.update(
                editing,
                occurredAt: draft.occurredAt,
                title: makeTitle(),
                note: note,
                payloadJSON: payloadJSON,
                weight: weight
            )
        } else {
            try service.create(
                pet: pet,
                type: type,
                occurredAt: draft.occurredAt,
                title: makeTitle(),
                note: note,
                payloadJSON: payloadJSON,
                weight: weight
            )
        }
    }

    // MARK: - 组装

    /// 主标题：优先用用户输入的关键字段
    private func makeTitle() -> String {
        switch type {
        case .vaccine:
            return draft.vaccineName.trimmed.isEmpty ? type.localizedTitle : draft.vaccineName.trimmed
        case .deworming:
            return draft.dewormingScope.localizedTitle
        case .medication:
            return draft.drugName.trimmed.isEmpty ? type.localizedTitle : draft.drugName.trimmed
        case .visit:
            return draft.hospital.trimmed.isEmpty ? type.localizedTitle : draft.hospital.trimmed
        case .symptom:
            return draft.symptomType.localizedTitle
        case .weight:
            return "\(draft.weightText) kg"
        case .daily:
            return type.localizedTitle
        }
    }

    private func buildPayloadJSON() -> String {
        switch type {
        case .vaccine:
            return PayloadCoding.encode(VaccinePayload(
                vaccineName: draft.vaccineName.trimmed,
                hospital: draft.hospital.nilIfEmpty,
                batchNumber: draft.batchNumber.nilIfEmpty,
                nextDate: draft.hasNextDate ? draft.nextDate : nil,
                adverseReaction: draft.adverseReaction.nilIfEmpty
            ))
        case .deworming:
            return PayloadCoding.encode(DewormingPayload(
                scope: draft.dewormingScope,
                drugName: draft.drugName.nilIfEmpty,
                nextDate: draft.hasNextDate ? draft.nextDate : nil
            ))
        case .medication:
            return PayloadCoding.encode(MedicationPayload(
                drugName: draft.drugName.trimmed,
                dosage: draft.dosage.trimmed,
                frequency: draft.frequency.trimmed,
                startDate: draft.hasMedicationRange ? draft.startDate : nil,
                endDate: draft.hasMedicationRange ? draft.endDate : nil,
                route: draft.route.nilIfEmpty
            ))
        case .visit:
            return PayloadCoding.encode(VisitPayload(
                hospital: draft.hospital.trimmed,
                doctor: draft.doctor.nilIfEmpty,
                chiefComplaint: draft.chiefComplaint.nilIfEmpty,
                diagnosis: draft.diagnosis.nilIfEmpty,
                treatment: draft.treatment.nilIfEmpty,
                cost: Double(draft.costText),
                followUpDate: draft.hasFollowUp ? draft.followUpDate : nil
            ))
        case .symptom:
            return PayloadCoding.encode(SymptomPayload(
                symptomType: draft.symptomType,
                severity: draft.severity,
                duration: draft.duration.nilIfEmpty
            ))
        case .weight:
            return PayloadCoding.encode(WeightPayload(
                weightKg: Double(draft.weightText) ?? 0,
                unit: "kg",
                bcs: draft.hasBCS ? draft.bcs : nil
            ))
        case .daily:
            return PayloadCoding.encode(DailyPayload(
                foodAmount: draft.foodAmount.nilIfEmpty,
                water: draft.water.nilIfEmpty,
                excretion: draft.excretion.nilIfEmpty,
                exercise: draft.exercise.nilIfEmpty,
                mood: draft.mood.nilIfEmpty
            ))
        }
    }

    /// 编辑时从记录回填草稿
    private static func fill(_ draft: inout RecordDraft, from record: Record) {
        switch record.type {
        case .vaccine:
            guard let p = record.payload(VaccinePayload.self) else { return }
            draft.vaccineName = p.vaccineName
            draft.hospital = p.hospital ?? ""
            draft.batchNumber = p.batchNumber ?? ""
            draft.adverseReaction = p.adverseReaction ?? ""
            draft.hasNextDate = p.nextDate != nil
            draft.nextDate = p.nextDate ?? record.occurredAt
        case .deworming:
            guard let p = record.payload(DewormingPayload.self) else { return }
            draft.dewormingScope = p.scope
            draft.drugName = p.drugName ?? ""
            draft.hasNextDate = p.nextDate != nil
            draft.nextDate = p.nextDate ?? record.occurredAt
        case .medication:
            guard let p = record.payload(MedicationPayload.self) else { return }
            draft.drugName = p.drugName
            draft.dosage = p.dosage
            draft.frequency = p.frequency
            draft.route = p.route ?? ""
            draft.hasMedicationRange = p.startDate != nil || p.endDate != nil
            draft.startDate = p.startDate ?? record.occurredAt
            draft.endDate = p.endDate ?? record.occurredAt
        case .visit:
            guard let p = record.payload(VisitPayload.self) else { return }
            draft.hospital = p.hospital
            draft.doctor = p.doctor ?? ""
            draft.chiefComplaint = p.chiefComplaint ?? ""
            draft.diagnosis = p.diagnosis ?? ""
            draft.treatment = p.treatment ?? ""
            draft.costText = p.cost.map { String($0) } ?? ""
            draft.hasFollowUp = p.followUpDate != nil
            draft.followUpDate = p.followUpDate ?? record.occurredAt
        case .symptom:
            guard let p = record.payload(SymptomPayload.self) else { return }
            draft.symptomType = p.symptomType
            draft.severity = p.severity
            draft.duration = p.duration ?? ""
        case .weight:
            guard let p = record.payload(WeightPayload.self) else { return }
            draft.weightText = String(p.weightKg)
            draft.hasBCS = p.bcs != nil
            draft.bcs = p.bcs ?? 5
        case .daily:
            guard let p = record.payload(DailyPayload.self) else { return }
            draft.foodAmount = p.foodAmount ?? ""
            draft.water = p.water ?? ""
            draft.excretion = p.excretion ?? ""
            draft.exercise = p.exercise ?? ""
            draft.mood = p.mood ?? ""
        }
    }
}

extension String {
    /// 去首尾空白
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 空串转 nil
    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
