import SwiftUI
import SwiftData

/// Übungsbibliothek mit Suche und Filtern nach Muskelgruppe, Typ, Ziel, Equipment, Hersteller und Schwierigkeit.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \Equipment.brand) private var equipment: [Equipment]

    @State private var search = ""
    @State private var muscle: MuscleGroup?
    @State private var category: ExerciseCategory?
    @State private var focus: TrainingFocus?
    @State private var kind: EquipmentKind?
    @State private var brand: String?
    @State private var machineID: String?
    @State private var difficulty: Difficulty?
    @State private var showNewExercise = false
    @State private var showNewEquipment = false

    private var brands: [String] {
        Array(Set(equipment.map(\.brand).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [Exercise] {
        let query = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale)
        let brandIDs: Set<String>? = brand.map { b in Set(equipment.filter { $0.brand == b }.flatMap(\.exerciseIDs)) }
        let machineIDs: Set<String>? = machineID.flatMap { id in equipment.first { $0.id == id } }.map { Set($0.exerciseIDs) }
        return exercises.filter { exercise in
            if !query.isEmpty {
                let name = exercise.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale)
                if !name.contains(query) && !exercise.primaryMuscle.title.lowercased().contains(query) { return false }
            }
            if let muscle, exercise.primaryMuscle != muscle && !exercise.secondaryMuscles.contains(muscle) { return false }
            if let category, exercise.category != category { return false }
            if let focus, !exercise.focus.contains(focus) { return false }
            if let kind, exercise.equipmentKind != kind { return false }
            if let difficulty, exercise.difficulty != difficulty { return false }
            if let brandIDs, !brandIDs.contains(exercise.id) { return false }
            if let machineIDs, !machineIDs.contains(exercise.id) { return false }
            return true
        }
    }

    private var grouped: [(MuscleGroup, [Exercise])] {
        let dict = Dictionary(grouping: filtered, by: \.primaryMuscle)
        return MuscleGroup.allCases.compactMap { group in
            guard let items = dict[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    private var hasFilters: Bool {
        muscle != nil || category != nil || focus != nil || kind != nil || brand != nil || machineID != nil || difficulty != nil
    }

    var body: some View {
        List {
            Section {
                filterBar
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            if grouped.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowBackground(Color.clear)
            }

            ForEach(grouped, id: \.0) { group, items in
                Section(group.title) {
                    ForEach(items) { exercise in
                        NavigationLink(value: AppDestination.exercise(id: exercise.id)) {
                            TrainingExerciseRow(exercise: exercise)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .navigationTitle("Übungen")
        .searchable(text: $search, prompt: "Übung suchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Eigene Übung", systemImage: "figure.strengthtraining.traditional") { showNewExercise = true }
                    Button("Eigenes Gerät", systemImage: "gearshape.2") { showNewEquipment = true }
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewExercise) { TrainingExerciseEditor() }
        .sheet(isPresented: $showNewEquipment) { TrainingEquipmentEditor(preselectedExerciseID: nil) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasFilters {
                    Button {
                        withAnimation(.snappy) {
                            muscle = nil; category = nil; focus = nil; kind = nil; brand = nil; machineID = nil; difficulty = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(Theme.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter zurücksetzen")
                }
                filterMenu("Muskel", value: muscle?.title) {
                    Picker("Muskelgruppe", selection: $muscle) {
                        Text("Alle").tag(MuscleGroup?.none)
                        ForEach(MuscleGroup.allCases) { Text($0.title).tag(MuscleGroup?.some($0)) }
                    }
                }
                filterMenu("Typ", value: category?.title) {
                    Picker("Übungstyp", selection: $category) {
                        Text("Alle").tag(ExerciseCategory?.none)
                        ForEach(ExerciseCategory.allCases) { Text($0.title).tag(ExerciseCategory?.some($0)) }
                    }
                }
                filterMenu("Ziel", value: focus?.title) {
                    Picker("Trainingsziel", selection: $focus) {
                        Text("Alle").tag(TrainingFocus?.none)
                        ForEach(TrainingFocus.allCases) { Text($0.title).tag(TrainingFocus?.some($0)) }
                    }
                }
                filterMenu("Equipment", value: kind?.title) {
                    Picker("Equipment", selection: $kind) {
                        Text("Alle").tag(EquipmentKind?.none)
                        ForEach(EquipmentKind.allCases) { Text($0.title).tag(EquipmentKind?.some($0)) }
                    }
                }
                filterMenu("Hersteller", value: machineID.flatMap { id in equipment.first { $0.id == id }?.displayName } ?? brand) {
                    Button("Alle Hersteller") { brand = nil; machineID = nil }
                    ForEach(brands, id: \.self) { b in
                        Menu(b) {
                            Button("Alle von \(b)") { brand = b; machineID = nil }
                            ForEach(equipment.filter { $0.brand == b }) { item in
                                Button(item.modelName.isEmpty ? item.name : item.modelName) { brand = nil; machineID = item.id }
                            }
                        }
                    }
                }
                filterMenu("Niveau", value: difficulty?.title) {
                    Picker("Schwierigkeit", selection: $difficulty) {
                        Text("Alle").tag(Difficulty?.none)
                        ForEach(Difficulty.allCases) { Text($0.title).tag(Difficulty?.some($0)) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xxs)
            .padding(.vertical, Theme.Space.xxs)
        }
    }

    private func filterMenu<Content: View>(_ title: String, value: String?, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(value ?? title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(value == nil ? Color.primary : Color.white)
            .background(value == nil ? Theme.fill : Theme.training, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Listenzeile einer Übung.
struct TrainingExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: exercise.equipmentKind.symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.training)
                .frame(width: 32, height: 32)
                .background(Theme.training.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                    if exercise.isCustom { Badge(text: "Eigene") }
                }
                Text("\(exercise.equipmentKind.title) · \(exercise.category.title) · \(exercise.difficulty.title)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Auswahl

/// Auswahl einer Übung (Hinzufügen, Tauschen, Planbearbeitung).
struct TrainingExercisePicker: View {
    let title: String
    let suggested: [Exercise]
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var muscle: MuscleGroup?

    private var filtered: [Exercise] {
        let query = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale)
        return exercises.filter { exercise in
            if let muscle, exercise.primaryMuscle != muscle { return false }
            guard !query.isEmpty else { return true }
            return exercise.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale).contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ChoiceChip(title: "Alle", isSelected: muscle == nil) { muscle = nil }
                            ForEach(MuscleGroup.allCases) { group in
                                ChoiceChip(title: group.title, isSelected: muscle == group) { muscle = group }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if !suggested.isEmpty && search.isEmpty && muscle == nil {
                    Section("Passende Alternativen") {
                        ForEach(suggested.prefix(8)) { exercise in
                            pickRow(exercise)
                        }
                    }
                }
                Section(search.isEmpty && muscle == nil ? "Alle Übungen" : "Ergebnisse") {
                    ForEach(filtered) { exercise in
                        pickRow(exercise)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Übung suchen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func pickRow(_ exercise: Exercise) -> some View {
        Button {
            onPick(exercise)
            dismiss()
        } label: {
            TrainingExerciseRow(exercise: exercise)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Mehrfachauswahl von Übungen (z. B. für Geräte oder bevorzugte Übungen).
struct TrainingExerciseMultiSelect: View {
    let title: String
    @Binding var selection: [String]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""

    var body: some View {
        List {
            ForEach(exercises.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { exercise in
                Button {
                    if let index = selection.firstIndex(of: exercise.id) {
                        selection.remove(at: index)
                    } else {
                        selection.append(exercise.id)
                    }
                } label: {
                    HStack {
                        TrainingExerciseRow(exercise: exercise)
                        Spacer()
                        if selection.contains(exercise.id) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.training)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Übung suchen")
    }
}

// MARK: - Editoren

/// Eigene Übung anlegen.
struct TrainingExerciseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var primary: MuscleGroup = .chest
    @State private var secondary: Set<MuscleGroup> = []
    @State private var category: ExerciseCategory = .compound
    @State private var kind: EquipmentKind = .machine
    @State private var difficulty: Difficulty = .beginner
    @State private var focus: Set<TrainingFocus> = [.hypertrophy]
    @State private var instructions = ""
    @State private var jointFriendly = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name der Übung", text: $name)
                }
                Section("Einordnung") {
                    Picker("Hauptmuskel", selection: $primary) {
                        ForEach(MuscleGroup.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Übungstyp", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Equipment", selection: $kind) {
                        ForEach(EquipmentKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Schwierigkeit", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Gelenkschonend", isOn: $jointFriendly)
                }
                Section("Weitere Muskeln") {
                    FlowLayout(spacing: 8) {
                        ForEach(MuscleGroup.allCases.filter { $0 != primary }) { group in
                            ChoiceChip(title: group.title, isSelected: secondary.contains(group)) {
                                if secondary.contains(group) { secondary.remove(group) } else { secondary.insert(group) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Trainingsziel") {
                    FlowLayout(spacing: 8) {
                        ForEach(TrainingFocus.allCases) { item in
                            ChoiceChip(title: item.title, isSelected: focus.contains(item)) {
                                if focus.contains(item) { focus.remove(item) } else { focus.insert(item) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Ausführung") {
                    TextField("Kurze Beschreibung (optional)", text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Eigene Übung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .buttonStyle(.glassProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let exercise = Exercise(id: "custom-\(UUID().uuidString.lowercased())", name: name.trimmingCharacters(in: .whitespaces),
                                primary: primary, secondary: Array(secondary), category: category, equipment: kind,
                                difficulty: difficulty, focus: Array(focus), instructions: instructions,
                                jointFriendly: jointFriendly, isCustom: true)
        context.insert(exercise)
        context.saveQuietly()
        dismiss()
    }
}

/// Eigenes Gerät anlegen (Marke, Modell, Typ, Gewichtsabstufung).
struct TrainingEquipmentEditor: View {
    let preselectedExerciseID: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Equipment.brand) private var existing: [Equipment]

    @State private var brand = ""
    @State private var modelName = ""
    @State private var kind: EquipmentKind = .machine
    @State private var increment: Double?
    @State private var exerciseIDs: [String] = []

    private var knownBrands: [String] {
        let base = ["Technogym", "Life Fitness", "Hammer Strength", "Matrix", "gym80", "Precor", "Cybex", "eGym", "Nautilus", "Panatta"]
        return Array(Set(base + existing.map(\.brand))).filter { !$0.isEmpty }.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gerät") {
                    HStack {
                        TextField("Hersteller", text: $brand)
                        Menu {
                            ForEach(knownBrands, id: \.self) { b in
                                Button(b) { brand = b }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Hersteller auswählen")
                    }
                    TextField("Modell (z. B. Leg Press)", text: $modelName)
                    Picker("Typ", selection: $kind) {
                        ForEach(EquipmentKind.allCases) { Text($0.title).tag($0) }
                    }
                    NumberField(title: "Kleinste Abstufung", value: $increment, unit: "kg", fractionDigits: 2)
                }
                Section {
                    NavigationLink {
                        TrainingExerciseMultiSelect(title: "Übungen", selection: $exerciseIDs)
                    } label: {
                        LabeledContent("Übungen an diesem Gerät", value: "\(exerciseIDs.count)")
                    }
                } footer: {
                    Text("Kern wertet Gewichte pro Gerät getrennt aus, weil Maschinen unterschiedlicher Hersteller nicht direkt vergleichbar sind.")
                }
            }
            .navigationTitle("Eigenes Gerät")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .buttonStyle(.glassProminent)
                        .disabled(modelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let preselectedExerciseID, exerciseIDs.isEmpty { exerciseIDs = [preselectedExerciseID] }
            }
        }
    }

    private func save() {
        let name = modelName.trimmingCharacters(in: .whitespaces)
        let item = Equipment(id: "custom-eq-\(UUID().uuidString.lowercased())", name: name,
                             brand: brand.trimmingCharacters(in: .whitespaces), modelName: name, kind: kind,
                             exerciseIDs: exerciseIDs, increment: increment, isCustom: true)
        context.insert(item)
        context.saveQuietly()
        dismiss()
    }
}
