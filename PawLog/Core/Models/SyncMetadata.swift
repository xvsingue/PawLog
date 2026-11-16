//
//  SyncMetadata.swift
//  PawLog
//
//  五个业务模型共用的同步元数据接口。字段本身写在各 @Model 里（带默认值，
//  保证旧 store 可迁移），这里只提供统一访问方式，便于 ChangeLog 与引擎泛型处理。
//

import Foundation

/// 可参与同步的模型
protocol SyncTracked: AnyObject {
    var id: UUID { get }
    var localUpdatedAt: Date { get set }
    var deviceID: String { get set }
    var deletedAt: Date? { get set }
    var changeTag: String { get set }
}

extension Pet: SyncTracked {}
extension Record: SyncTracked {}
extension WeightEntry: SyncTracked {}
extension Reminder: SyncTracked {}
extension Attachment: SyncTracked {}
