//
//  PetEditView.swift
//  PawLog
//
//  新建 / 编辑宠物档案。
//

import SwiftUI
import SwiftData

struct PetEditView: View {
    @StateObject private var viewModel: PetEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    init(service: PetService, pet: Pet? = nil) {
        _viewModel = StateObject(wrappedValue: PetEditViewModel(service: service, pet: pet))
    }

    var body: some View {
        Form {
            basicSection
            birthdaySection
            bodySection
            medicalSection
        }
        .navigationTitle(viewModel.isEditing ? String(localized: "pet.edit.title") : String(localized: "pet.add.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "common.save")) {
                    save()
                }
                .disabled(!viewModel.isValid)
                .accessibilityIdentifier("pet.save")
            }
        }
        .alert(String(localized: "pet.edit.error.save"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // MARK: - 基本信息

    private var basicSection: some View {
        Section(String(localized: "pet.section.basic")) {
            HStack {
                Text("pet.field.name")
                    .foregroundStyle(Theme.Palette.textPrimary)
                TextField(String(localized: "pet.field.name.placeholder"), text: $viewModel.name)
                    .multilineTextAlignment(.trailing)
            }
            Picker(String(localized: "pet.field.species"), selection: $viewModel.species) {
                ForEach(PetSpecies.allCases, id: \.self) { species in
                    Text(species.localizedKey.localized).tag(species)
                }
            }
            HStack {
                Text("pet.field.breed")
                    .foregroundStyle(Theme.Palette.textPrimary)
                TextField(String(localized: "pet.field.breed.placeholder"), text: $viewModel.breed)
                    .multilineTextAlignment(.trailing)
            }
            Picker(String(localized: "pet.field.sex"), selection: $viewModel.sex) {
                ForEach(PetSex.allCases, id: \.self) { sex in
                    Text(sex.localizedKey.localized).tag(sex)
                }
            }
        }
    }

    // MARK: - 生日

    private var birthdaySection: some View {
        Section(String(localized: "pet.section.birthday")) {
            Toggle(String(localized: "pet.field.hasBirthday"), isOn: $viewModel.hasBirthday)
                .tint(Theme.Palette.primary)
            if viewModel.hasBirthday {
                DatePicker(String(localized: "pet.field.birthday"), selection: $viewModel.birthday, displayedComponents: .date)
                Toggle(String(localized: "pet.field.birthEstimated"), isOn: $viewModel.birthEstimated)
                    .tint(Theme.Palette.primary)
            }
        }
    }

    // MARK: - 身体

    private var bodySection: some View {
        Section(String(localized: "pet.section.body")) {
            Toggle(String(localized: "pet.field.hasNeutered"), isOn: $viewModel.hasNeutered)
                .tint(Theme.Palette.primary)
            if viewModel.hasNeutered {
                Toggle(String(localized: "pet.field.neutered"), isOn: $viewModel.neutered)
                    .tint(Theme.Palette.primary)
            }
            HStack {
                Text("pet.field.idealWeight")
                    .foregroundStyle(Theme.Palette.textPrimary)
                TextField(String(localized: "pet.field.idealWeight.placeholder"), text: $viewModel.idealWeightText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
        }
    }

    // MARK: - 医疗

    private var medicalSection: some View {
        Section(String(localized: "pet.section.medical")) {
            HStack(alignment: .top) {
                Text("pet.field.allergies")
                    .foregroundStyle(Theme.Palette.textPrimary)
                TextField(String(localized: "pet.field.allergies.placeholder"), text: $viewModel.allergies, axis: .vertical)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("pet.field.foodBrand")
                    .foregroundStyle(Theme.Palette.textPrimary)
                TextField(String(localized: "pet.field.foodBrand.placeholder"), text: $viewModel.foodBrand)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("pet.field.chipID")
                    .foregroundStyle(Theme.Palette.textPrimary)
                TextField(String(localized: "pet.field.chipID.placeholder"), text: $viewModel.chipID)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
        }
    }

    // MARK: - 保存

    private func save() {
        do {
            try viewModel.save()
            dismiss()
        } catch {
            errorMessage = String(localized: "pet.edit.error.save")
        }
    }
}

#Preview("PetEditView") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Pet.self, configurations: config)
    let context = container.mainContext
    return NavigationStack {
        PetEditView(service: PetService(context: context))
    }
    .modelContainer(container)
}
