import SwiftUI
import SwiftData

/// Fitnessstudio-Profile mit verfügbarer Ausstattung. Das aktive Profil steuert
/// Übungsvorschläge, Alternativen und die Planerstellung.
struct GymProfilesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]

    @State private var newGym: GymProfile?

    private var activeID: UUID? {
        if let id = prefs.activeGymID.flatMap(UUID.init(uuidString:)), gyms.contains(where: { $0.id == id }) { return id }
        return gyms.first(where: \.isDefault)?.id ?? gyms.first?.id
    }

    var body: some View {
        List {
            Section {
                ForEach(gyms) { gym in
                    NavigationLink {
                        TrainingGymEditor(gym: gym)
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            RowLabel(title: gym.name.isEmpty ? "Ohne Namen" : gym.name,
                                     subtitle: "\(gym.availableKinds.count) Ausstattungsarten · \(gym.equipmentIDs.count) Geräte",
                                     symbol: activeID == gym.id ? "checkmark.circle.fill" : "building.2",
                                     tint: activeID == gym.id ? Theme.training : .secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if activeID != gym.id {
                            Button("Aktiv", systemImage: "checkmark.circle") { prefs.activeGymID = gym.id.uuidString }
                                .tint(Theme.training)
                        }
                    }
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Das aktive Studio bestimmt, welche Übungen Kern bei Plänen und beim Tauschen vorschlägt.")
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .navigationTitle("Gym-Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let gym = GymProfile(name: "Neues Studio", kinds: EquipmentKind.allCases)
                    context.insert(gym)
                    context.saveQuietly()
                    newGym = gym
                } label: {
                    Label("Studio hinzufügen", systemImage: "plus")
                }
            }
        }
        .navigationDestination(item: $newGym) { gym in
            TrainingGymEditor(gym: gym)
        }
        .overlay {
            if gyms.isEmpty {
                ContentUnavailableView("Kein Studio", systemImage: "building.2",
                                       description: Text("Lege ein Studio an, um Pläne an deine Geräte anzupassen."))
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let gym = gyms[index]
            if prefs.activeGymID == gym.id.uuidString { prefs.activeGymID = nil }
            context.delete(gym)
        }
        context.saveQuietly()
    }
}

/// Bearbeitung eines Studio-Profils.
struct TrainingGymEditor: View {
    @Bindable var gym: GymProfile

    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \Equipment.brand) private var equipment: [Equipment]

    @State private var showNewEquipment = false

    private var brands: [String] {
        Array(Set(equipment.map { $0.brand.isEmpty ? "Ohne Hersteller" : $0.brand })).sorted()
    }

    private var isActive: Bool { prefs.activeGymID == gym.id.uuidString }

    var body: some View {
        Form {
            Section {
                TextField("Name des Studios", text: $gym.name)
                Button {
                    prefs.activeGymID = gym.id.uuidString
                } label: {
                    Label(isActive ? "Aktives Studio" : "Als aktives Studio verwenden",
                          systemImage: isActive ? "checkmark.circle.fill" : "circle")
                }
                .disabled(isActive)
            }

            Section {
                ForEach(EquipmentKind.allCases) { kind in
                    Toggle(isOn: kindBinding(kind)) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } header: {
                Text("Verfügbare Ausstattung")
            } footer: {
                Text("Übungen mit Körpergewicht sind immer verfügbar.")
            }

            ForEach(brands, id: \.self) { brand in
                Section(brand) {
                    ForEach(equipment.filter { ($0.brand.isEmpty ? "Ohne Hersteller" : $0.brand) == brand }) { item in
                        Toggle(isOn: equipmentBinding(item)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.modelName.isEmpty ? item.name : item.modelName)
                                Text(item.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Eigenes Gerät anlegen", systemImage: "plus") { showNewEquipment = true }
                NavigationLink {
                    TrainingExerciseMultiSelect(title: "Bevorzugte Übungen", selection: $gym.preferredExerciseIDs)
                } label: {
                    LabeledContent("Bevorzugte Übungen", value: "\(gym.preferredExerciseIDs.count)")
                }
            }

            Section("Notizen") {
                TextField("z. B. Öffnungszeiten, Besonderheiten", text: $gym.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(gym.name.isEmpty ? "Studio" : gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewEquipment) {
            TrainingEquipmentEditor(preselectedExerciseID: nil)
        }
        .onDisappear { context.saveQuietly() }
    }

    private func kindBinding(_ kind: EquipmentKind) -> Binding<Bool> {
        Binding(
            get: { gym.availableKinds.contains(kind) },
            set: { isOn in
                var kinds = gym.availableKinds.filter { $0 != kind }
                if isOn { kinds.append(kind) }
                gym.availableKinds = kinds
            }
        )
    }

    private func equipmentBinding(_ item: Equipment) -> Binding<Bool> {
        Binding(
            get: { gym.equipmentIDs.contains(item.id) },
            set: { isOn in
                gym.equipmentIDs.removeAll { $0 == item.id }
                if isOn {
                    gym.equipmentIDs.append(item.id)
                    if !gym.availableKinds.contains(item.kind) { gym.availableKinds.append(item.kind) }
                }
            }
        )
    }
}
