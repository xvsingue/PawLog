//
//  RecordType+Display.swift
//  PawLog
//
//  记录类型的展示映射：标题 key、SF Symbol、主色。
//

import SwiftUI

extension RecordType {
    /// 本地化标题 key
    var titleKey: String {
        switch self {
        case .vaccine: "record.type.vaccine"
        case .deworming: "record.type.deworming"
        case .medication: "record.type.medication"
        case .visit: "record.type.visit"
        case .symptom: "record.type.symptom"
        case .weight: "record.type.weight"
        case .daily: "record.type.daily"
        }
    }

    /// 本地化标题
    var localizedTitle: String {
        String(localized: String.LocalizationValue(titleKey))
    }

    /// 图标
    var symbolName: String {
        switch self {
        case .vaccine: "syringe"
        case .deworming: "bug"
        case .medication: "pills"
        case .visit: "cross.case"
        case .symptom: "exclamationmark.triangle"
        case .weight: "scalemass"
        case .daily: "sun.max"
        }
    }

    /// 图标主色。症状为预警色，其余用主色。
    var tint: Color {
        self == .symptom ? Theme.Palette.danger : Theme.Palette.primary
    }
}

extension DewormingScope {
    var titleKey: String {
        switch self {
        case .internalOnly: "record.scope.internal"
        case .externalOnly: "record.scope.external"
        case .both: "record.scope.both"
        }
    }

    var localizedTitle: String {
        String(localized: String.LocalizationValue(titleKey))
    }
}

extension SymptomType {
    var titleKey: String {
        switch self {
        case .vomit: "record.symptom.vomit"
        case .diarrhea: "record.symptom.diarrhea"
        case .cough: "record.symptom.cough"
        case .skin: "record.symptom.skin"
        case .energy: "record.symptom.energy"
        case .appetite: "record.symptom.appetite"
        case .excretion: "record.symptom.excretion"
        }
    }

    var localizedTitle: String {
        String(localized: String.LocalizationValue(titleKey))
    }
}
