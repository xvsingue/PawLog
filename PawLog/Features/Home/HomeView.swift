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

    private var petService: PetService { PetService(context: modelContext) }
    private var recordService: RecordService { RecordService(context: modelContext) }

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
                        TimelineView(pet: selectedPet, service: recordService) {
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
                    QuickRecordSheet(pet: pet, service: recordService)
                }
            }
            .sheet(isPresented: $showingPetList, onDismiss: reload) {
                PetListView(service: petService, showsCloseButton: true)
            }
            .onAppear(perform: reload)
        }
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
        pets.move(fromOffsets: source, toOffset: destination)
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
