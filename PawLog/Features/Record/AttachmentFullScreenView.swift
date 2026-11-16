//
//  AttachmentFullScreenView.swift
//  PawLog
//
//  全屏查看单张照片：后台读取原图并解码，支持删除（墓碑语义）。
//

import SwiftUI
import SwiftData

struct AttachmentFullScreenView: View {
    let attachment: Attachment
    let service: AttachmentService
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "attachment.action.delete"), role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
            }
            .confirmationDialog(
                String(localized: "attachment.delete.confirm.title"),
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "attachment.delete.confirm.action"), role: .destructive) {
                    deleteAttachment()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "attachment.delete.confirm.message"))
            }
            .alert(String(localized: "attachment.error.title"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
        .task {
            image = await AttachmentThumbnailLoader.makeFileTask(
                url: service.fileURL(for: attachment),
                maxPixelSize: AttachmentStore.maxImagePixelSize
            ).value
        }
    }

    private func deleteAttachment() {
        do {
            try service.delete(attachment)
            onDelete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("AttachmentFullScreenView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
        Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self,
        configurations: config
    )
    let record = Record(type: .visit, occurredAt: Date(), title: "复查")
    container.mainContext.insert(record)
    let attachment = Attachment(
        record: record,
        kind: .image,
        localPath: "attachments/\(record.id.uuidString)/preview.jpg"
    )
    container.mainContext.insert(attachment)
    try! container.mainContext.save()
    return AttachmentFullScreenView(
        attachment: attachment,
        service: AttachmentService(context: container.mainContext)
    ) {}
    .modelContainer(container)
}
