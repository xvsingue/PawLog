//
//  TimelineView.swift
//  PawLog
//
//  时间线：按 月 → 日 倒序分组，同日超过 3 条折叠；顶部类型筛选。
//

import SwiftUI
import SwiftData

struct TimelineView: View {
    let pet: Pet?
    let service: RecordService
    let onAdd: () -> Void

    @Query(sort: \Record.occurredAt, order: .reverse)
    private var allRecords: [Record]

    @State private var filter: RecordType?
    @State private var expandedDays: Set<Date> = []

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if filteredRecords.isEmpty {
                EmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "record.timeline.empty.title",
                    description: "record.timeline.empty.description",
                    buttonTitle: "record.timeline.empty.action",
                    action: onAdd
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.groupSpacing) {
                        ForEach(TimelineGrouping.group(filteredRecords)) { month in
                            monthSection(month)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.pageMargin)
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
        }
        .background(Theme.Palette.background)
    }

    // MARK: - 筛选

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                filterChip(title: "record.filter.all", type: nil)
                ForEach(RecordType.allCases, id: \.self) { type in
                    filterChip(title: type.titleKey, type: type)
                }
            }
            .padding(.horizontal, Theme.Spacing.pageMargin)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(Theme.Palette.background)
    }

    private func filterChip(title: String, type: RecordType?) -> some View {
        Button {
            filter = type
        } label: {
            Chip(
                title: LocalizedStringKey(title),
                isSelected: filter == type
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分组

    private func monthSection(_ month: TimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(month.title)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Palette.textPrimary)

            ForEach(month.days) { day in
                daySection(day)
            }
        }
    }

    private func daySection(_ day: TimelineDay) -> some View {
        let isExpanded = expandedDays.contains(day.id)
        let visible = isExpanded ? day.records : Array(day.records.prefix(TimelineGrouping.collapsedLimit))
        let hiddenCount = day.records.count - visible.count

        return VStack(alignment: .leading, spacing: 0) {
            Text(day.title)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.bottom, Theme.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                    NavigationLink {
                        RecordDetailView(record: record, service: service)
                    } label: {
                        TimelineRow(record: record)
                    }
                    .buttonStyle(.plain)

                    if index < visible.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(Theme.Spacing.cardPadding)
            .background(Theme.Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            if hiddenCount > 0 || isExpanded {
                Button {
                    if isExpanded {
                        expandedDays.remove(day.id)
                    } else {
                        expandedDays.insert(day.id)
                    }
                } label: {
                    Text(isExpanded
                         ? String(localized: "record.timeline.collapse")
                         : String(localized: "record.timeline.expand \(hiddenCount)"))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.primary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Theme.Spacing.lg)
    }

    // MARK: - 数据

    private var filteredRecords: [Record] {
        guard let pet else { return [] }
        return allRecords.filter { record in
            record.pet?.id == pet.id && (filter == nil || record.type == filter)
        }
    }
}

#Preview("TimelineView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
        configurations: config
    )
    let context = container.mainContext
    let pet = Pet(name: "咪咪", species: .cat)
    context.insert(pet)
    context.insert(Record(pet: pet, type: .vaccine, occurredAt: Date(), title: "猫三联"))
    context.insert(Record(pet: pet, type: .weight, occurredAt: Date(), title: "4.2 kg"))
    try! context.save()
    return NavigationStack {
        TimelineView(pet: pet, service: RecordService(context: context)) {}
    }
    .modelContainer(container)
}
