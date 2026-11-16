//
//  ReminderListView.swift
//  PawLog
//
//  提醒中心：即将到期 / 已过期两组，显示剩余天数，点击跳记录详情。
//

import SwiftUI
import SwiftData

struct ReminderListView: View {
    let pet: Pet
    let reminderService: ReminderService
    let recordService: RecordService

    @StateObject private var viewModel: ReminderListViewModel
    @Environment(EntitlementService.self) private var entitlements
    @State private var selectedRecord: Record?
    @State private var showingPaywall = false

    init(pet: Pet, reminderService: ReminderService, recordService: RecordService) {
        self.pet = pet
        self.reminderService = reminderService
        self.recordService = recordService
        _viewModel = StateObject(wrappedValue: ReminderListViewModel(pet: pet, service: reminderService))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.upcoming.isEmpty && viewModel.overdue.isEmpty {
                    EmptyState(
                        systemImage: "bell",
                        title: "reminder.list.empty.title",
                        description: "reminder.list.empty.description",
                        buttonTitle: "reminder.list.empty.action",
                        action: { selectedRecord = nil }
                    )
                } else {
                    List {
                        if !viewModel.upcoming.isEmpty {
                            Section(String(localized: "reminder.section.upcoming")) {
                                ForEach(viewModel.upcoming, id: \.id) { reminder in
                                    reminderRow(reminder)
                                }
                            }
                        }
                        if !viewModel.overdue.isEmpty {
                            Section(String(localized: "reminder.section.overdue")) {
                                ForEach(viewModel.overdue, id: \.id) { reminder in
                                    reminderRow(reminder)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "reminder.list.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.reload() }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .navigationDestination(item: $selectedRecord) { record in
                RecordDetailView(record: record, service: recordService, reminderService: reminderService)
            }
        }
    }

    // MARK: - 行

    /// 免费用户可排通知的提醒 id（按 dueAt 最近的若干条）
    private var notifiableIDs: Set<UUID> {
        guard let limit = entitlements.reminderLimit else { return [] }
        let enabled = (viewModel.upcoming + viewModel.overdue)
            .filter(\.enabled)
            .sorted { $0.dueAt < $1.dueAt }
        return Set(enabled.prefix(limit).map(\.id))
    }

    /// 超出免费上限：数据保留但不会排通知
    private func isOverLimit(_ reminder: Reminder) -> Bool {
        entitlements.reminderLimit != nil && reminder.enabled && !notifiableIDs.contains(reminder.id)
    }

    private func reminderRow(_ reminder: Reminder) -> some View {
        let days = viewModel.daysRemaining(for: reminder)
        return HStack(spacing: Theme.Spacing.md) {
            Button {
                if isOverLimit(reminder) {
                    showingPaywall = true
                } else {
                    openDetail(reminder)
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: reminder.kind.symbolName)
                        .font(.system(size: 20))
                        .foregroundStyle(reminder.kind.tint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(reminder.kind.localizedTitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(reminder.dueAt.formatted(.dateTime.year().month().day()))
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        if isOverLimit(reminder) {
                            Text(String(localized: "reminder.freeLimit.hint"))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.accent)
                        }
                    }

                    Spacer()

                    daysBadge(days: days)
                }
                .opacity(isOverLimit(reminder) ? 0.5 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 关闭开关时 ReminderService 会撤销该提醒的全部待发通知；
            // 超出免费上限的提醒仍保留且可开关，只是不排通知
            Toggle("", isOn: Binding(
                get: { reminder.enabled },
                set: { viewModel.setEnabled(reminder, enabled: $0) }
            ))
            .labelsHidden()
            .tint(Theme.Palette.primary)
            .accessibilityLabel(String(localized: "reminder.action.toggle"))
        }
        .padding(.vertical, Theme.Spacing.xs)
        .swipeActions {
            Button(String(localized: "reminder.action.done")) {
                viewModel.markDone(reminder)
            }
            .tint(Theme.Palette.primary)
        }
    }

    /// 跳转到该提醒来源记录的详情
    private func openDetail(_ reminder: Reminder) {
        if let record = pet.records.first(where: {
            $0.id == reminder.sourceRecordID && $0.deletedAt == nil
        }) {
            selectedRecord = record
        }
    }

    private func daysBadge(days: Int) -> some View {
        let text: String
        let color: Color
        if days > 0 {
            text = String(localized: "reminder.days.remaining \(days)")
            color = days <= 7 ? Theme.Palette.accent : Theme.Palette.textSecondary
        } else if days == 0 {
            text = String(localized: "reminder.days.today")
            color = Theme.Palette.accent
        } else {
            text = String(localized: "reminder.days.overdue \(-days)")
            color = Theme.Palette.danger
        }
        return Text(text)
            .font(Theme.Typography.footnote)
            .foregroundStyle(color)
    }
}

// MARK: - 提醒类型展示

extension ReminderKind {
    var symbolName: String {
        switch self {
        case .vaccine: "syringe"
        case .deworming: "bug"
        case .medication: "pills"
        case .visit: "cross.case"
        case .custom: "bell"
        }
    }

    var tint: Color {
        Theme.Palette.primary
    }

    var titleKey: String {
        switch self {
        case .vaccine: "record.type.vaccine"
        case .deworming: "record.type.deworming"
        case .medication: "record.type.medication"
        case .visit: "record.type.visit"
        case .custom: "reminder.kind.custom"
        }
    }

    var localizedTitle: String {
        String(localized: String.LocalizationValue(titleKey))
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self,
        configurations: config
    )
    let context = container.mainContext
    let pet = Pet(name: "咪咪", species: .cat)
    context.insert(pet)
    let reminder = Reminder(pet: pet, kind: .vaccine, dueAt: Date().addingTimeInterval(7 * 86400))
    context.insert(reminder)
    let notif = NotificationService(center: UNUserNotificationCenterAdapter())
    let service = ReminderService(context: context, notificationService: notif)
    return ReminderListView(pet: pet, reminderService: service, recordService: RecordService(context: context))
        .modelContainer(container)
        .environment(EntitlementService(context: context))
        .environment(StoreKitService())
}
