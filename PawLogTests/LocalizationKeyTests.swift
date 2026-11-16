//
//  LocalizationKeyTests.swift
//  PawLogTests
//
//  扫描源码中的 String(localized:) 与 Text("...")，断言 key 均存在于 Localizable.xcstrings。
//

import XCTest
@testable import PawLog

final class LocalizationKeyTests: XCTestCase {
    /// 所有引用的本地化 key 必须存在于 String Catalog
    func testAllReferencedKeysExistInCatalog() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repoRoot.appendingPathComponent("PawLog/Localizable.xcstrings")
        let catalogKeys = try loadCatalogKeys(at: catalogURL)
        XCTAssertFalse(catalogKeys.isEmpty, "String Catalog 不应为空")

        let sourceRoot = repoRoot.appendingPathComponent("PawLog")
        let sourceFiles = try swiftFiles(in: sourceRoot)
        XCTAssertFalse(sourceFiles.isEmpty, "未找到源码文件")

        var references: [String: String] = [:]
        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            for key in Self.extractKeys(from: text) where references[key] == nil {
                references[key] = file.lastPathComponent
            }
        }
        XCTAssertFalse(references.isEmpty, "未提取到任何本地化 key，检查扫描规则")

        var missing: [String] = []
        for (key, file) in references.sorted(by: { $0.key < $1.key }) {
            if catalogKeys.contains(key) { continue }
            // 带格式占位符的 key（如 "summary.age.months %lld"）按前缀匹配
            if catalogKeys.contains(where: { $0.hasPrefix(key + " ") }) { continue }
            missing.append("\(key)（\(file)）")
        }

        XCTAssertTrue(missing.isEmpty, "以下 key 在 Localizable.xcstrings 中缺失：\(missing)")
    }

    // MARK: - 工具

    private func loadCatalogKeys(at url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        return Set(strings.keys)
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            files.append(url)
        }
        return files
    }

    /// 提取 String(localized: "...") 与 Text("...") 中的 key（去掉插值部分）
    static func extractKeys(from source: String) -> Set<String> {
        let patterns = [
            #"String\(localized:\s*"((?:[^"\\]|\\.)*)""#,
            #"Text\("((?:[^"\\]|\\.)*)""#,
        ]
        var keys: Set<String> = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let matchRange = Range(match.range(at: 1), in: source) else { continue }
                let raw = String(source[matchRange])
                if let key = baseKey(from: raw) {
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    /// 插值 key 只保留稳定前缀，如 "summary.age.months \(months)" → "summary.age.months"
    private static func baseKey(from raw: String) -> String? {
        let base: String
        if let range = raw.range(of: "\\(") {
            base = String(raw[..<range.lowerBound])
        } else {
            base = raw
        }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
