//
//  ModelCleanup.swift
//  PawLog
//
//  业务数据删除的唯一实现：逐对象删除，避免批量删除在反向关系上触发
//  "Constraint trigger violation: Batch delete failed due to mandatory OTO nullify inverse"。
//  清空全部数据与备份恢复共用此处，原则上不再出现第二套删除逻辑。
//

import Foundation
import SwiftData

@MainActor
enum ModelCleanup {
    /// 删除全部业务数据（宠物、记录、体重、提醒、附件）。
    /// 不删除 Entitlement：清空数据或恢复备份都不应抹掉本地购买状态。
    /// 调用方负责 save。
    static func deleteBusinessData(in context: ModelContext) throws {
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) { context.delete(attachment) }
        for record in try context.fetch(FetchDescriptor<Record>()) { context.delete(record) }
        for entry in try context.fetch(FetchDescriptor<WeightEntry>()) { context.delete(entry) }
        for reminder in try context.fetch(FetchDescriptor<Reminder>()) { context.delete(reminder) }
        for pet in try context.fetch(FetchDescriptor<Pet>()) { context.delete(pet) }
    }
}
