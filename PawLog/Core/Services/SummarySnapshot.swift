//
//  SummarySnapshot.swift
//  PawLog
//
//  就诊摘要快照：把宠物数据整理成与渲染无关的纯数据，便于测试与复用（PDF / 长图）。
//

import Foundation

/// 就诊摘要快照
struct SummarySnapshot {
    /// 头部基本信息（已完成本地化与格式化）
    struct Header {
        var petName: String
        var speciesBreed: String
        var sex: String
        var age: String
        var chipID: String
        var weight: String
        var allergies: String
    }

    /// 一条摘要记录
    struct Entry: Identifiable {
        let id: UUID
        var date: Date
        var type: RecordType
        var typeTitle: String
        var title: String
        var detail: String
    }

    /// 体重变化摘要
    struct WeightChange {
        var startText: String
        var endText: String
        var changeText: String
    }

    var header: Header
    var records: [Entry]
    var weightChange: WeightChange?
    var medicationAndVisits: [Entry]
    var rangeDays: Int
    var generatedAt: Date
}

// MARK: - 构建

enum SummarySnapshotBuilder {
    /// 默认取最近 90 天
    static let defaultRangeDays = 90

    /// 生成快照。只纳入窗口内的记录，按时间倒序。
    static func make(
        pet: Pet,
        now: Date = Date(),
        days: Int = defaultRangeDays,
        calendar: Calendar = .current,
        unit: WeightUnit = WeightFormatter.unit
    ) -> SummarySnapshot {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -days,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast

        let entries = pet.records
            .filter { $0.occurredAt >= cutoff && $0.occurredAt <= now }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map { makeEntry($0, unit: unit) }

        return SummarySnapshot(
            header: makeHeader(pet: pet, now: now, calendar: calendar, unit: unit),
            records: entries,
            weightChange: makeWeightChange(pet: pet, cutoff: cutoff, calendar: calendar, unit: unit),
            medicationAndVisits: entries.filter { $0.type == .medication || $0.type == .visit },
            rangeDays: days,
            generatedAt: now
        )
    }

    // MARK: 头部

    private static func makeHeader(pet: Pet, now: Date, calendar: Calendar, unit: WeightUnit) -> SummarySnapshot.Header {
        let breed = pet.breed?.trimmed.isEmpty == false ? pet.breed!.trimmed : nil
        let species = pet.species.localizedKey.localized
        let speciesBreed = breed.map { "\(species) · \($0)" } ?? species

        return SummarySnapshot.Header(
            petName: pet.name,
            speciesBreed: speciesBreed,
            sex: pet.sex.localizedKey.localized,
            age: ageText(birthday: pet.birthday, now: now, calendar: calendar),
            chipID: pet.chipID?.trimmed.isEmpty == false ? pet.chipID!.trimmed : "summary.value.missing".localized,
            weight: latestWeightText(pet: pet, unit: unit),
            allergies: pet.allergies?.trimmed.isEmpty == false ? pet.allergies!.trimmed : "summary.value.none".localized
        )
    }

    /// 年龄文案：不满 1 年按月，满 1 年按岁
    private static func ageText(birthday: Date?, now: Date, calendar: Calendar) -> String {
        guard let birthday else { return "summary.value.unknown".localized }
        let components = calendar.dateComponents([.month], from: birthday, to: now)
        let months = max(0, components.month ?? 0)
        if months < 12 {
            return String(localized: "summary.age.months \(months)")
        }
        return String(localized: "summary.age.years \(months / 12)")
    }

    private static func latestWeightText(pet: Pet, unit: WeightUnit) -> String {
        let latest = pet.weightEntries
            .sorted { $0.date < $1.date }
            .last
        guard let latest else { return "summary.value.unknown".localized }
        return WeightFormatter.string(latest.weightKg, unit: unit)
    }

    // MARK: 记录

    private static func makeEntry(_ record: Record, unit: WeightUnit) -> SummarySnapshot.Entry {
        SummarySnapshot.Entry(
            id: record.id,
            date: record.occurredAt,
            type: record.type,
            typeTitle: record.type.localizedTitle,
            title: record.type == .weight
                ? WeightFormatter.string(record.payload(WeightPayload.self)?.weightKg ?? 0, unit: unit)
                : record.title,
            detail: detailText(for: record, unit: unit)
        )
    }

    /// 各类型的关键字段，空字段跳过，用「 · 」连接
    private static func detailText(for record: Record, unit: WeightUnit) -> String {
        var parts: [String] = []

        switch record.type {
        case .vaccine:
            if let payload = record.payload(VaccinePayload.self) {
                append(payload.hospital, to: &parts)
                append(payload.nextDate.map { nextDateText($0) }, to: &parts)
            }
        case .deworming:
            if let payload = record.payload(DewormingPayload.self) {
                parts.append(payload.scope.localizedTitle)
                append(payload.drugName, to: &parts)
            }
        case .medication:
            if let payload = record.payload(MedicationPayload.self) {
                append(payload.drugName, to: &parts)
                append(payload.dosage, to: &parts)
                append(payload.frequency, to: &parts)
            }
        case .visit:
            if let payload = record.payload(VisitPayload.self) {
                append(payload.hospital, to: &parts)
                append(payload.diagnosis, to: &parts)
            }
        case .symptom:
            if let payload = record.payload(SymptomPayload.self) {
                parts.append(payload.symptomType.localizedTitle)
                parts.append(String(localized: "summary.severity \(payload.severity)"))
            }
        case .weight:
            // 体重已作为标题展示，关键字段只保留 BCS
            if let payload = record.payload(WeightPayload.self), let bcs = payload.bcs {
                parts.append(String(localized: "weight.bcs.label \(bcs)"))
            }
        case .daily:
            if let payload = record.payload(DailyPayload.self) {
                append(payload.foodAmount, to: &parts)
                append(payload.excretion, to: &parts)
                append(payload.mood, to: &parts)
            }
        }

        return parts.joined(separator: " · ")
    }

    private static func append(_ value: String?, to parts: inout [String]) {
        guard let value, !value.trimmed.isEmpty else { return }
        parts.append(value.trimmed)
    }

    private static func nextDateText(_ date: Date) -> String {
        String(localized: "summary.nextDate \(date.formatted(.dateTime.year().month().day()))")
    }

    // MARK: 体重摘要

    private static func makeWeightChange(
        pet: Pet,
        cutoff: Date,
        calendar: Calendar,
        unit: WeightUnit
    ) -> SummarySnapshot.WeightChange? {
        // 同日取最后一条
        var latestByDay: [Date: WeightEntry] = [:]
        for entry in pet.weightEntries where entry.date >= cutoff {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = latestByDay[day], existing.date >= entry.date { continue }
            latestByDay[day] = entry
        }
        let points = latestByDay.values.sorted { $0.date < $1.date }
        guard let first = points.first, let last = points.last else { return nil }

        let changeText: String
        if first.weightKg > 0 {
            let percent = (last.weightKg - first.weightKg) / first.weightKg
            changeText = percent.formatted(.percent.precision(.fractionLength(1)))
        } else {
            changeText = "summary.value.unknown".localized
        }

        return SummarySnapshot.WeightChange(
            startText: WeightFormatter.string(first.weightKg, unit: unit),
            endText: WeightFormatter.string(last.weightKg, unit: unit),
            changeText: changeText
        )
    }
}
