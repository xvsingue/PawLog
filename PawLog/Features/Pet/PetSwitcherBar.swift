//
//  PetSwitcherBar.swift
//  PawLog
//
//  宠物切换条：头像 56 + 名字 13，选中 2pt 主色描边。长按拖动可排序。
//

import SwiftUI
import UniformTypeIdentifiers

struct PetSwitcherBar: View {
    let pets: [Pet]
    let selectedID: UUID?
    let onSelect: (Pet) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(pets) { pet in
                    Button {
                        onSelect(pet)
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            avatar(for: pet)
                            Text(pet.name)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .draggable(pet.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        move(items, onto: pet)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.pageMargin)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    /// 拖动到目标宠物位置
    private func move(_ items: [String], onto target: Pet) -> Bool {
        guard let raw = items.first,
              let draggedID = UUID(uuidString: raw),
              let from = pets.firstIndex(where: { $0.id == draggedID }),
              let to = pets.firstIndex(where: { $0.id == target.id }),
              from != to
        else { return false }

        onMove(IndexSet(integer: from), to > from ? to + 1 : to)
        return true
    }

    private func avatar(for pet: Pet) -> some View {
        let isSelected = pet.id == selectedID
        return Circle()
            .fill(Theme.Palette.fill)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: pet.species == .cat ? "cat" : "dog.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Palette.textSecondary)
            )
            .overlay(
                Circle()
                    .stroke(isSelected ? Theme.Palette.primary : .clear, lineWidth: 2)
            )
    }
}

#Preview("PetSwitcherBar") {
    let pets = [
        Pet(name: "咪咪", species: .cat),
        Pet(name: "旺财", species: .dog),
        Pet(name: "球球", species: .other)
    ]
    return PetSwitcherBar(pets: pets, selectedID: pets.first?.id, onSelect: { _ in }, onMove: { _, _ in })
        .background(Theme.Palette.background)
}
