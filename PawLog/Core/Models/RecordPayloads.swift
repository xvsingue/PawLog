//
//  RecordPayloads.swift
//  PawLog
//
//  剩余五类记录的载荷：驱虫 / 用药 / 就诊 / 症状 / 日常。字段照 PRD 5.2。
//  解码时缺字段一律回退默认值，兼容旧数据。
//

import Foundation

// MARK: - 驱虫

/// 驱虫范围
enum DewormingScope: String, Codable, CaseIterable {
    case internalOnly = "internal"
    case externalOnly = "external"
    case both
}

/// 驱虫记录载荷
struct DewormingPayload: RecordPayload {
    static let recordType: RecordType = .deworming

    var scope: DewormingScope
    var drugName: String?
    var nextDate: Date?

    init(scope: DewormingScope, drugName: String? = nil, nextDate: Date? = nil) {
        self.scope = scope
        self.drugName = drugName
        self.nextDate = nextDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawScope = try c.decodeIfPresent(String.self, forKey: .scope)
        scope = rawScope.flatMap(DewormingScope.init(rawValue:)) ?? .both
        drugName = try c.decodeIfPresent(String.self, forKey: .drugName)
        nextDate = try c.decodeIfPresent(Date.self, forKey: .nextDate)
    }
}

// MARK: - 用药

/// 用药记录载荷
struct MedicationPayload: RecordPayload {
    static let recordType: RecordType = .medication

    var drugName: String
    var dosage: String
    var frequency: String
    var startDate: Date?
    var endDate: Date?
    var route: String?

    init(
        drugName: String,
        dosage: String,
        frequency: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        route: String? = nil
    ) {
        self.drugName = drugName
        self.dosage = dosage
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.route = route
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drugName = try c.decodeIfPresent(String.self, forKey: .drugName) ?? ""
        dosage = try c.decodeIfPresent(String.self, forKey: .dosage) ?? ""
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency) ?? ""
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        route = try c.decodeIfPresent(String.self, forKey: .route)
    }
}

// MARK: - 就诊

/// 就诊记录载荷
struct VisitPayload: RecordPayload {
    static let recordType: RecordType = .visit

    var hospital: String
    var doctor: String?
    var chiefComplaint: String?
    var diagnosis: String?
    var treatment: String?
    var cost: Double?
    var followUpDate: Date?

    init(
        hospital: String,
        doctor: String? = nil,
        chiefComplaint: String? = nil,
        diagnosis: String? = nil,
        treatment: String? = nil,
        cost: Double? = nil,
        followUpDate: Date? = nil
    ) {
        self.hospital = hospital
        self.doctor = doctor
        self.chiefComplaint = chiefComplaint
        self.diagnosis = diagnosis
        self.treatment = treatment
        self.cost = cost
        self.followUpDate = followUpDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hospital = try c.decodeIfPresent(String.self, forKey: .hospital) ?? ""
        doctor = try c.decodeIfPresent(String.self, forKey: .doctor)
        chiefComplaint = try c.decodeIfPresent(String.self, forKey: .chiefComplaint)
        diagnosis = try c.decodeIfPresent(String.self, forKey: .diagnosis)
        treatment = try c.decodeIfPresent(String.self, forKey: .treatment)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        followUpDate = try c.decodeIfPresent(Date.self, forKey: .followUpDate)
    }
}

// MARK: - 症状

/// 症状类型
enum SymptomType: String, Codable, CaseIterable {
    case vomit
    case diarrhea
    case cough
    case skin
    case energy
    case appetite
    case excretion
}

/// 症状记录载荷
struct SymptomPayload: RecordPayload {
    static let recordType: RecordType = .symptom

    var symptomType: SymptomType
    /// 严重度 1–3
    var severity: Int
    var duration: String?

    init(symptomType: SymptomType, severity: Int, duration: String? = nil) {
        self.symptomType = symptomType
        self.severity = severity
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try c.decodeIfPresent(String.self, forKey: .symptomType)
        symptomType = rawType.flatMap(SymptomType.init(rawValue:)) ?? .excretion
        let rawSeverity = try c.decodeIfPresent(Int.self, forKey: .severity) ?? 1
        severity = min(max(rawSeverity, 1), 3)
        duration = try c.decodeIfPresent(String.self, forKey: .duration)
    }
}

// MARK: - 日常

/// 日常记录载荷
struct DailyPayload: RecordPayload {
    static let recordType: RecordType = .daily

    var foodAmount: String?
    var water: String?
    var excretion: String?
    var exercise: String?
    var mood: String?

    init(
        foodAmount: String? = nil,
        water: String? = nil,
        excretion: String? = nil,
        exercise: String? = nil,
        mood: String? = nil
    ) {
        self.foodAmount = foodAmount
        self.water = water
        self.excretion = excretion
        self.exercise = exercise
        self.mood = mood
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodAmount = try c.decodeIfPresent(String.self, forKey: .foodAmount)
        water = try c.decodeIfPresent(String.self, forKey: .water)
        excretion = try c.decodeIfPresent(String.self, forKey: .excretion)
        exercise = try c.decodeIfPresent(String.self, forKey: .exercise)
        mood = try c.decodeIfPresent(String.self, forKey: .mood)
    }
}
