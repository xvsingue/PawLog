//
//  RecordPayload.swift
//  PawLog
//
//  记录差异化字段的载荷。各类型实现 RecordPayload 协议，序列化为 JSON 存入 Record.payloadJSON。
//  每个类型都自定义解码：缺字段回退默认值，保证旧数据可读、不崩溃。
//

import Foundation
import OSLog

/// 记录载荷协议
protocol RecordPayload: Codable {
    static var recordType: RecordType { get }
}

/// 载荷 JSON 编解码
enum PayloadCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 编码为 JSON 字符串
    static func encode<T: RecordPayload>(_ payload: T) -> String {
        guard let data = try? encoder.encode(payload) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 疫苗

/// 疫苗记录载荷
struct VaccinePayload: RecordPayload {
    static let recordType: RecordType = .vaccine

    var vaccineName: String
    var hospital: String?
    var batchNumber: String?
    var nextDate: Date?
    var adverseReaction: String?

    init(
        vaccineName: String,
        hospital: String? = nil,
        batchNumber: String? = nil,
        nextDate: Date? = nil,
        adverseReaction: String? = nil
    ) {
        self.vaccineName = vaccineName
        self.hospital = hospital
        self.batchNumber = batchNumber
        self.nextDate = nextDate
        self.adverseReaction = adverseReaction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vaccineName = try c.decodeIfPresent(String.self, forKey: .vaccineName) ?? ""
        hospital = try c.decodeIfPresent(String.self, forKey: .hospital)
        batchNumber = try c.decodeIfPresent(String.self, forKey: .batchNumber)
        nextDate = try c.decodeIfPresent(Date.self, forKey: .nextDate)
        adverseReaction = try c.decodeIfPresent(String.self, forKey: .adverseReaction)
    }
}

// MARK: - 体重

/// 体重记录载荷
struct WeightPayload: RecordPayload {
    static let recordType: RecordType = .weight

    var weightKg: Double
    var unit: String?
    var bcs: Int?

    init(weightKg: Double, unit: String? = nil, bcs: Int? = nil) {
        self.weightKg = weightKg
        self.unit = unit
        self.bcs = bcs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 0
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        bcs = try c.decodeIfPresent(Int.self, forKey: .bcs)
    }
}

// MARK: - Record 编解码辅助

extension Record {
    private static let logger = Logger(subsystem: "com.Lennox.PawLog", category: "RecordPayload")

    /// 解码指定类型的载荷。解析失败返回 nil（记录日志），不抛错、不崩溃。
    func payload<T: RecordPayload>(_ type: T.Type) -> T? {
        guard let data = payloadJSON.data(using: .utf8) else {
            Self.logger.error("载荷解码失败：payloadJSON 无法转为 UTF-8 数据，record=\(self.id, privacy: .public)")
            return nil
        }
        do {
            return try PayloadCoding.decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("载荷解码失败：record=\(self.id, privacy: .public) type=\(String(describing: T.self), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 编码并存储载荷
    func setPayload<T: RecordPayload>(_ payload: T) {
        payloadJSON = PayloadCoding.encode(payload)
    }
}
