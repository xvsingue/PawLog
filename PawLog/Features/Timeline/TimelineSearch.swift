//
//  TimelineSearch.swift
//  PawLog
//
//  时间线搜索：匹配标题、备注、类型名、药品名、医院名。
//  忽略大小写与所有空白（含中文全角空格），纯函数实现便于单元测试。
//

import Foundation

enum TimelineSearch {
    /// 归一化：小写 + 去掉全部空白
    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    /// 一条记录可被检索的文本
    static func searchableText(for record: Record) -> String {
        var parts: [String] = [record.title, record.type.localizedTitle]
        if let note = record.note { parts.append(note) }

        switch record.type {
        case .medication:
            if let payload = record.payload(MedicationPayload.self) {
                parts.append(payload.drugName)
                if let route = payload.route { parts.append(route) }
            }
        case .deworming:
            if let name = record.payload(DewormingPayload.self)?.drugName { parts.append(name) }
        case .visit:
            if let payload = record.payload(VisitPayload.self) {
                parts.append(payload.hospital)
                if let doctor = payload.doctor { parts.append(doctor) }
            }
        case .vaccine:
            if let hospital = record.payload(VaccinePayload.self)?.hospital { parts.append(hospital) }
        case .weight, .symptom, .daily:
            break
        }
        return parts.joined(separator: "\n")
    }

    /// 是否命中查询。空查询视为不筛选。
    static func matches(_ record: Record, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        return normalized(searchableText(for: record)).contains(needle)
    }

    /// 过滤记录；空查询返回原数组
    static func filter(_ records: [Record], query: String) -> [Record] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return records }
        return records.filter { normalized(searchableText(for: $0)).contains(needle) }
    }
}
