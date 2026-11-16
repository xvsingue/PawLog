//
//  LocalDirectoryTransport.swift
//  PawLog
//
//  本地目录实现的"远端"：变更以 JSON 文件落在指定目录，两台设备（两个独立
//  ModelContainer）指向同一目录即可模拟同步。接入 CloudKit 时整体替换本类。
//

import Foundation

/// 目录传输实现
@MainActor
final class LocalDirectoryTransport: SyncTransport {
    private let directory: URL
    private let fileManager: FileManager
    private let fileName: String

    init(directory: URL, fileManager: FileManager = .default, fileName: String = "remote-changes.json") {
        self.directory = directory
        self.fileManager = fileManager
        self.fileName = fileName
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    // MARK: - SyncTransport

    /// 拉取 since 之后的变更；since 为空或找不到时返回全部
    func pull(since changeTag: String) async throws -> [RemoteChange] {
        let all = try load()
        guard !changeTag.isEmpty,
              let index = all.lastIndex(where: { $0.changeTag == changeTag }) else {
            return all
        }
        let start = all.index(after: index)
        return Array(all[start...])
    }

    /// 推送变更；返回发生冲突的 entityID。
    /// 本实现按同一套 LWW + 删除优先规则自行合并，保证"服务端"结果确定。
    func push(_ changes: [LocalChange]) async throws -> [UUID] {
        var existing = try load()
        var conflicts: [UUID] = []

        for change in changes {
            // 幂等：同一实体 + 同一 changeTag 直接跳过
            if existing.contains(where: { $0.dedupeKey == change.dedupeKey }) { continue }

            let incoming = RemoteChange(local: change)
            if let index = existing.lastIndex(where: { $0.entityID == change.entityID && $0.entityName == change.entityName }) {
                let current = existing[index]
                // 同一设备的新变更直接覆盖（不是冲突）
                if current.deviceID == incoming.deviceID {
                    existing[index] = incoming
                    continue
                }
                conflicts.append(change.entityID)
                if ConflictResolver.resolve(local: change, remote: current) == .local {
                    existing[index] = incoming
                }
            } else {
                existing.append(incoming)
            }
        }

        try save(existing)
        return Array(Set(conflicts))
    }

    /// 当前全部远端变更（测试与排查用）
    func allChanges() throws -> [RemoteChange] {
        try load()
    }

    // MARK: - 文件读写

    private func load() throws -> [RemoteChange] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RemoteChange].self, from: data)
    }

    private func save(_ changes: [RemoteChange]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(changes).write(to: fileURL, options: .atomic)
    }
}
