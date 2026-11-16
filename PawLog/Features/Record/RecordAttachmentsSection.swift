//
//  RecordAttachmentsSection.swift
//  PawLog
//
//  记录详情的照片区：PhotosPicker 系统选择器（不需要相册权限）、
//  异步缩略图、全屏查看与删除。
//

import SwiftUI
import SwiftData
import PhotosUI

struct RecordAttachmentsSection: View {
    let record: Record

    @Environment(\.modelContext) private var modelContext
    @State private var attachments: [Attachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var preview: Attachment?
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var service: AttachmentService {
        AttachmentService(context: modelContext)
    }

    private var remaining: Int {
        max(0, AttachmentService.maxPerRecord - attachments.count)
    }

    var body: some View {
        Section(String(localized: "attachment.section.title")) {
            if attachments.isEmpty {
                Text(String(localized: "attachment.empty.hint"))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88), spacing: Theme.Spacing.sm)],
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(attachments, id: \.id) { attachment in
                        Button {
                            preview = attachment
                        } label: {
                            AsyncAttachmentThumbnail(data: attachment.thumbnailData)
                                .frame(height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.input))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "attachment.action.delete"), role: .destructive) {
                                delete(attachment)
                            }
                        }
                        .accessibilityLabel(String(localized: "attachment.viewer.title"))
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            if remaining > 0 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: remaining,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(String(localized: "attachment.action.add"), systemImage: "plus")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.primary)
                        .frame(minHeight: 44)
                }
                .disabled(isImporting)
            } else {
                Text(String(localized: "attachment.limit.hint \(AttachmentService.maxPerRecord)"))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .task { refresh() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
        .fullScreenCover(isPresented: previewBinding) {
            if let attachment = preview {
                AttachmentFullScreenView(attachment: attachment, service: service) {
                    refresh()
                }
            }
        }
        .alert(String(localized: "attachment.error.title"), isPresented: errorBinding) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // MARK: - 数据

    private var previewBinding: Binding<Bool> {
        Binding(
            get: { preview != nil },
            set: { if !$0 { preview = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func refresh() {
        attachments = service.attachments(for: record)
    }

    // MARK: - 动作

    private func importPicked(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            pickerItems = []
        }

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AttachmentError.unsupportedImage
                }
                _ = try await service.addImage(data, to: record)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        refresh()
    }

    private func delete(_ attachment: Attachment) {
        do {
            try service.delete(attachment)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("RecordAttachmentsSection") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self,
        Attachment.self, Entitlement.self, ChangeLog.self, ConflictLog.self,
        configurations: config
    )
    let record = Record(type: .visit, occurredAt: Date(), title: "复查")
    container.mainContext.insert(record)
    try! container.mainContext.save()
    return List {
        RecordAttachmentsSection(record: record)
    }
    .modelContainer(container)
}
