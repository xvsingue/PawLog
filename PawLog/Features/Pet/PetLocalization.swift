//
//  PetLocalization.swift
//  PawLog
//
//  宠物枚举的本地化 key 映射。
//

import SwiftUI

extension PetSpecies {
    var localizedKey: String {
        switch self {
        case .cat: return "pet.species.cat"
        case .dog: return "pet.species.dog"
        case .other: return "pet.species.other"
        }
    }
}

extension PetSex {
    var localizedKey: String {
        switch self {
        case .male: return "pet.sex.male"
        case .female: return "pet.sex.female"
        case .unknown: return "pet.sex.unknown"
        }
    }
}

extension String {
    /// 通过 key 获取本地化字符串
    var localized: String {
        String(localized: String.LocalizationValue(self))
    }
}
