//
//  HomeView.swift
//  PawLog
//
//  首页：宠物切换条 + 时间线。M2 阶段只做记录与时间线，不含提醒与摘要。
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var pets: [Pet] = []
    @State private var selectedPetID: UUID?
    @State private var showingQuickRecord = false
    @State private var showingPetList = false
    @State private var showingReminders = false
    @State private var showingSettings = false
    @State private var showingWeightTrend = false
    /// 体重页空状态点「去记录」时，等 Sheet 关闭后再打开记录表单
    @State private var pendingQuickRecord = false

    private var petService: PetService { PetService(context: modelContext) }
    private var recordService: RecordService {
        RecordService(context: modelContext, reminderService: reminderService)
    }
    private var weightService: WeightTrendService { WeightTrendService() }
    private var reminderService: ReminderService {
        ReminderService(context: modelContext, notificationService: NotificationService())
    }

    var body: some View {
        NavigationStack {
            Group {
                if pets.isEmpty {
                    EmptyState(
                        systemImage: "pawprint",
                        title: "pet.list.empty.title",
                        description: "pet.list.empty.description",
                        buttonTitle: "pet.list.empty.action",
                        action: { showingPetList = true },
                        buttonIdentifier: "home.addPet"
                    )
                } else {
                    VStack(spacing: 0) {
                        PetSwitcherBar(
                            pets: pets,
                            selectedID: selectedPetID,
                            onSelect: { selectedPetID = $0.id },
                            onMove: movePets
                        )
                        if let pet = selectedPet {
                            WeightCardView(pet: pet, service: weightService) {
                                showingWeightTrend = true
                            }
                            .padding(.horizontal, Theme.Spacing.pageMargin)
                            .padding(.bottom, Theme.Spacing.md)
                        }
                        TimelineView(pet: selectedPet, service: recordService, reminderService: reminderService) {
                            showingQuickRecord = true
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "home.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPetList = true
                    } label: {
                        Image(systemName: "pawprint")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingReminders = true
                    } label: {
                        Image(systemName: "bell")
                    }
                    .disabled(selectedPet == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("home.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQuickRecord = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("home.addRecord")
                    .disabled(selectedPet == nil)
                }
            }
            .sheet(isPresented: $showingQuickRecord, onDismiss: reload) {
                if let pet = selectedPet {
                    QuickRecordSheet(pet: pet, service: recordService, reminderService: reminderService)
                }
            }
            .sheet(isPresented: $showingPetList, onDismiss: reload) {
                PetListView(service: petService, showsCloseButton: true)
            }
            .sheet(isPresented: $showingSettings, onDismiss: reload) {
                SettingsView()
            }
            .sheet(isPresented: $showingReminders) {
                if let pet = selectedPet {
                    ReminderListView(pet: pet, reminderService: reminderService, recordService: recordService)
                }
            }
            .sheet(isPresented: $showingWeightTrend, onDismiss: handleWeightSheetDismiss) {
                if let pet = selectedPet {
                    WeightTrendView(pet: pet, service: weightService) {
                        pendingQuickRecord = true
                        showingWeightTrend = false
                    }
                }
            }
            .onAppear(perform: reload)
        }
    }

    /// 体重页空状态「去记录」：等体重 Sheet 关闭后再打开记录表单
    private func handleWeightSheetDismiss() {
        guard pendingQuickRecord else { return }
        pendingQuickRecord = false
        showingQuickRecord = true
    }

    private var selectedPet: Pet? {
        guard let selectedPetID else { return pets.first }
        return pets.first { $0.id == selectedPetID } ?? pets.first
    }

    private func reload() {
        pets = (try? petService.fetchPets()) ?? []
        if let selectedPetID, pets.contains(where: { $0.id == selectedPetID }) {
            return
        }
        selectedPetID = pets.first?.id
    }

    private func movePets(fromOffsets source: IndexSet, toOffset destination: Int) {
        try? petService.movePets(fromOffsets: source, toOffset: destination)
        pets = (try? petService.fetchPets()) ?? pets
    }
}

#Preview("HomeView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Pet.self, Record.self, WeightEntry.self, Reminder.self, Attachment.self,
        configurations: config
    )
    let context = container.mainContext
    let pet = Pet(name: "咪咪", species: .cat)
    context.insert(pet)
    context.insert(Record(pet: pet, type: .vaccine, occurredAt: Date(), title: "猫三联"))
    try! context.save()
    return HomeView()
        .modelContainer(container)
}
