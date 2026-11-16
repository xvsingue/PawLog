//
//  PetListView.swift
//  PawLog
//
//  宠物列表：展示、新建入口、编辑、删除（需输入名称确认）。
//

import SwiftUI
import SwiftData

struct PetListView: View {
    @StateObject private var viewModel: PetListViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementService.self) private var entitlements
    @State private var showingAddPet = false
    @State private var showingPaywall = false
    @State private var petToDelete: Pet?
    @State private var deleteConfirmName = ""

    /// 以 Sheet 呈现时显示"完成"按钮
    var showsCloseButton: Bool = false

    init(service: PetService, showsCloseButton: Bool = false) {
        _viewModel = StateObject(wrappedValue: PetListViewModel(service: service))
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.pets.isEmpty {
                    EmptyState(
                        systemImage: "pawprint",
                        title: "pet.list.empty.title",
                        description: "pet.list.empty.description",
                        buttonTitle: "pet.list.empty.action",
                        action: { addPet() },
                        buttonIdentifier: "pet.addFirst"
                    )
                } else {
                    List {
                        ForEach(viewModel.pets) { pet in
                            NavigationLink {
                                PetEditView(service: viewModel.service, pet: pet)
                            } label: {
                                PetRow(pet: pet)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    petToDelete = pet
                                    deleteConfirmName = ""
                                } label: {
                                    Label("pet.list.action.delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "pet.list.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addPet()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "common.done")) {
                            dismiss()
                        }
                        .accessibilityIdentifier("pet.done")
                    }
                }
            }
            .sheet(isPresented: $showingAddPet, onDismiss: viewModel.loadPets) {
                NavigationStack {
                    PetEditView(service: viewModel.service)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert(
                String(localized: "pet.delete.confirm.title"),
                isPresented: Binding(
                    get: { petToDelete != nil },
                    set: { if !$0 { petToDelete = nil } }
                )
            ) {
                TextField(String(localized: "pet.delete.confirm.placeholder"), text: $deleteConfirmName)
                Button(String(localized: "common.cancel"), role: .cancel) {
                    petToDelete = nil
                }
                Button(String(localized: "pet.delete.confirm.action"), role: .destructive) {
                    guard let pet = petToDelete, deleteConfirmName == pet.name else { return }
                    viewModel.deletePet(pet)
                    petToDelete = nil
                }
            } message: {
                if let pet = petToDelete {
                    Text(String(localized: "pet.delete.confirm.message \(viewModel.recordCount(for: pet))"))
                }
            }
            .onAppear {
                viewModel.loadPets()
            }
        }
    }

    // MARK: - 操作

    /// 新建宠物：免费版超过 1 只时先引导订阅
    private func addPet() {
        if entitlements.canAddPet(currentCount: viewModel.pets.count) {
            showingAddPet = true
        } else {
            showingPaywall = true
        }
    }
}

private struct PetRow: View {
    let pet: Pet

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.Palette.fill)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: pet.species == .cat ? "cat" : "dog.fill")
                        .foregroundStyle(Theme.Palette.textSecondary)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var subtitle: String {
        var parts: [String] = [pet.species.localizedKey.localized]
        if let breed = pet.breed, !breed.isEmpty {
            parts.append(breed)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("PetListView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self, Entitlement.self, configurations: config)
    let context = container.mainContext
    context.insert(Pet(name: "咪咪", species: .cat, breed: "英短"))
    context.insert(Pet(name: "旺财", species: .dog))
    try! context.save()
    return PetListView(service: PetService(context: context))
        .modelContainer(container)
        .environment(EntitlementService(context: context))
        .environment(StoreKitService())
}
