import SwiftUI
import SwiftData

/// Plan bearbeiten: Trainingstage, Übungen, Sätze, Wiederholungen, Pausen und Supersätze.
struct PlanDetailView: View {
    let planID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutStore.self) private var workouts
    @Environment(AppRouter.self) private var router
    @Query private var matches: [WorkoutPlan]
    @Query private var allPlans: [WorkoutPlan]
    @Query private var exercises: [Exercise]

    @State private var pickerTemplate: WorkoutTemplate?
    @State private var renameTemplate: WorkoutTemplate?
    @State private var renameText = ""
    @State private var showDelete = false
    @State private var showRationale = false

    init(planID: UUID) {
        self.planID = planID
        let id = planID
        _matches = Query(filter: #Predicate<WorkoutPlan> { $0.id == id })
    }

    private var exerciseMap: [String: Exercise] {
        Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Group {
            if let plan = matches.first {
                content(plan)
            } else {
                ContentUnavailableView("Plan nicht gefunden", systemImage: "questionmark.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ plan: WorkoutPlan) -> some View {
        List {
            WorkoutPlanHeaderSection(plan: plan, showRationale: $showRationale, onActivate: { activate(plan) })

            ForEach(plan.sortedTemplates) { template in
                Section {
                    ForEach(template.exercises) { item in
                        NavigationLink {
                            TrainingTemplateExerciseEditor(template: template, itemID: item.id)
                        } label: {
                            templateRow(item)
                        }
                    }
                    .onDelete { offsets in
                        var list = template.exercises
                        list.remove(atOffsets: offsets)
                        template.exercises = list
                        context.saveQuietly()
                    }
                    .onMove { source, destination in
                        var list = template.exercises
                        list.move(fromOffsets: source, toOffset: destination)
                        template.exercises = list
                        context.saveQuietly()
                    }

                    Button("Übung hinzufügen", systemImage: "plus") { pickerTemplate = template }
                } header: {
                    HStack {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let last = template.lastPerformedAt {
                            Text("· zuletzt \(Fmt.shortDate(last))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Jetzt starten", systemImage: "play.fill") { start(template, plan: plan) }
                            Button("Umbenennen", systemImage: "pencil") {
                                renameText = template.name
                                renameTemplate = template
                            }
                            Button("Duplizieren", systemImage: "plus.square.on.square") { duplicate(template, in: plan) }
                            Divider()
                            Button("Trainingstag löschen", systemImage: "trash", role: .destructive) { deleteTemplate(template, in: plan) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Optionen für \(template.name)")
                    }
                    .textCase(nil)
                }
            }

            Section {
                Button("Trainingstag hinzufügen", systemImage: "calendar.badge.plus") { addTemplate(to: plan) }
            }

            Section {
                Button("Plan löschen", role: .destructive) { showDelete = true }
            } footer: {
                Text("Absolvierte Trainings bleiben im Verlauf erhalten.")
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: TrainingExport.text(for: plan, exercises: exerciseMap)) {
                    Label("Plan teilen", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $pickerTemplate) { template in
            TrainingExercisePicker(title: "Übung hinzufügen", suggested: []) { exercise in
                add(exercise, to: template)
            }
        }
        .alert("Trainingstag umbenennen", isPresented: Binding(get: { renameTemplate != nil }, set: { if !$0 { renameTemplate = nil } })) {
            TextField("Name", text: $renameText)
            Button("Abbrechen", role: .cancel) { renameTemplate = nil }
            Button("Sichern") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if let renameTemplate, !trimmed.isEmpty { renameTemplate.name = trimmed }
                context.saveQuietly()
                renameTemplate = nil
            }
        }
        .confirmationDialog("Plan löschen?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("„\(plan.name)“ löschen", role: .destructive) {
                AuditLog.record(context, actor: .user, summary: "Trainingsplan gelöscht: \(plan.name)",
                                entityType: EntityType.plan, entityID: plan.id.uuidString)
                context.delete(plan)
                context.saveQuietly()
                dismiss()
            }
        }
    }

    private func templateRow(_ item: TemplateExercise) -> some View {
        HStack(spacing: Theme.Space.s) {
            if let group = item.supersetGroup {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.training)
                    .frame(width: 4, height: 30)
                    .accessibilityLabel("Supersatz \(group)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseMap[item.exerciseID]?.name ?? "Unbekannte Übung")
                Text(templateDetail(item))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func templateDetail(_ item: TemplateExercise) -> String {
        var detail = "\(item.sets) × \(TrainingMath.repRange(min: item.repMin, max: item.repMax))"
        if let rir = item.targetRIR { detail += " · RIR \(rir)" }
        detail += " · \(item.restSeconds) s Pause"
        if item.warmupSets > 0 { detail += " · \(item.warmupSets) Aufwärmen" }
        return detail
    }

    // MARK: Aktionen

    private func activate(_ plan: WorkoutPlan) {
        for other in allPlans { other.isActive = other.id == plan.id }
        context.saveQuietly()
    }

    private func start(_ template: WorkoutTemplate, plan: WorkoutPlan) {
        workouts.start(template: template, plan: plan, name: template.name, in: context)
        router.isWorkoutPresented = true
    }

    private func add(_ exercise: Exercise, to template: WorkoutTemplate) {
        var item = TemplateExercise(exerciseID: exercise.id)
        if exercise.category == .compound {
            (item.repMin, item.repMax, item.restSeconds) = (6, 10, 120)
        } else if exercise.category == .cardio || exercise.category == .mobility {
            item.sets = 1
            item.repMin = 10
            item.repMax = 15
            item.restSeconds = 60
            item.targetRIR = nil
        } else {
            (item.repMin, item.repMax, item.restSeconds) = (10, 15, 75)
        }
        var list = template.exercises
        list.append(item)
        template.exercises = list
        context.saveQuietly()
    }

    private func addTemplate(to plan: WorkoutPlan) {
        let letters = ["A", "B", "C", "D", "E", "F", "G"]
        let index = plan.templates.count
        let template = WorkoutTemplate(name: "Tag \(index < letters.count ? letters[index] : "\(index + 1)")", order: index)
        plan.templates.append(template)
        plan.daysPerWeek = max(plan.daysPerWeek, plan.templates.count)
        context.saveQuietly()
    }

    private func duplicate(_ template: WorkoutTemplate, in plan: WorkoutPlan) {
        let copies = template.exercises.map { item -> TemplateExercise in
            var copy = item
            copy.id = UUID()
            return copy
        }
        let copy = WorkoutTemplate(name: "\(template.name) (Kopie)", order: plan.templates.count, exercises: copies)
        copy.notes = template.notes
        plan.templates.append(copy)
        context.saveQuietly()
    }

    private func deleteTemplate(_ template: WorkoutTemplate, in plan: WorkoutPlan) {
        plan.templates.removeAll { $0.id == template.id }
        context.delete(template)
        for (index, item) in plan.sortedTemplates.enumerated() { item.order = index }
        context.saveQuietly()
    }
}

private struct WorkoutPlanHeaderSection: View {
    @Bindable var plan: WorkoutPlan
    @Binding var showRationale: Bool
    let onActivate: () -> Void

    @State private var deloadRefresh = 0

    var body: some View {
        Section {
            TextField("Name des Plans", text: $plan.name)
                .font(.headline)
            Toggle("Aktiver Plan", isOn: Binding(get: { plan.isActive }, set: { if $0 { onActivate() } else { plan.isActive = false } }))
            Stepper(value: $plan.daysPerWeek, in: 1...7) {
                LabeledContent("Tage pro Woche", value: "\(plan.daysPerWeek)")
            }
            TextField("Notizen", text: $plan.notes, axis: .vertical)
                .lineLimit(1...4)
            if !plan.rationale.isEmpty {
                DisclosureGroup("Begründung von Kern", isExpanded: $showRationale) {
                    Text(plan.rationale)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if deloadRefresh >= 0, let until = TrainingDeload.activeUntil(planID: plan.id) {
                HStack {
                    Label("Leichtere Woche bis \(Fmt.shortDate(until))", systemImage: "leaf")
                        .font(.subheadline)
                        .foregroundStyle(Theme.positive)
                    Spacer()
                    Button("Beenden") {
                        TrainingDeload.end(planID: plan.id)
                        deloadRefresh += 1
                    }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Einstellungen einer geplanten Übung.
struct TrainingTemplateExerciseEditor: View {
    @Bindable var template: WorkoutTemplate
    let itemID: UUID

    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query private var allEquipment: [Equipment]
    @Query private var exercises: [Exercise]

    @State private var item: TemplateExercise?
    @State private var startWeight: Double?

    var body: some View {
        Form {
            if let binding = itemBinding {
                let exercise = exercises.first { $0.id == binding.wrappedValue.exerciseID }
                Section {
                    LabeledContent("Übung", value: exercise?.name ?? binding.wrappedValue.exerciseID)
                    let machines = allEquipment.filter { $0.exerciseIDs.contains(binding.wrappedValue.exerciseID) }
                    if !machines.isEmpty {
                        Picker("Gerät", selection: binding.equipmentID) {
                            Text("Kein bestimmtes Gerät").tag(String?.none)
                            ForEach(machines) { Text($0.displayName).tag(String?.some($0.id)) }
                        }
                    }
                }
                Section("Sätze & Wiederholungen") {
                    Stepper("Arbeitssätze: \(binding.wrappedValue.sets)", value: binding.sets, in: 1...10)
                    Stepper("Aufwärmsätze: \(binding.wrappedValue.warmupSets)", value: binding.warmupSets, in: 0...4)
                    Stepper("Wiederholungen min.: \(binding.wrappedValue.repMin)", value: Binding(
                        get: { binding.wrappedValue.repMin },
                        set: { binding.wrappedValue.repMin = $0; if binding.wrappedValue.repMax < $0 { binding.wrappedValue.repMax = $0 } }
                    ), in: 1...50)
                    Stepper("Wiederholungen max.: \(binding.wrappedValue.repMax)", value: Binding(
                        get: { binding.wrappedValue.repMax },
                        set: { binding.wrappedValue.repMax = $0; if binding.wrappedValue.repMin > $0 { binding.wrappedValue.repMin = $0 } }
                    ), in: 1...50)
                    Picker("Reserve (RIR)", selection: binding.targetRIR) {
                        Text("Keine Vorgabe").tag(Int?.none)
                        ForEach(0...5, id: \.self) { Text("RIR \($0)").tag(Int?.some($0)) }
                    }
                }
                Section("Pause & Supersatz") {
                    Picker("Pause", selection: binding.restSeconds) {
                        ForEach([30, 45, 60, 75, 90, 120, 150, 180, 240, 300], id: \.self) { Text("\($0) s").tag($0) }
                    }
                    Picker("Supersatz", selection: binding.supersetGroup) {
                        Text("Keiner").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text("Gruppe \($0)").tag(Int?.some($0)) }
                    }
                }
                Section {
                    NumberField(title: "Startgewicht", value: $startWeight, unit: prefs.weightUnit.symbol, fractionDigits: 2)
                } header: {
                    Text("Nächstes Training")
                } footer: {
                    Text("Optional. Wird beim nächsten Start dieses Trainingstags übernommen – sonst nutzt Kern deine letzten Werte.")
                }
                Section("Notiz") {
                    TextField("z. B. Sitzposition 4, enger Griff", text: binding.notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            } else {
                Text("Übung nicht gefunden.")
            }
        }
        .navigationTitle("Übung planen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            item = template.exercises.first { $0.id == itemID }
            if let item {
                startWeight = TrainingTargetWeights.get(templateID: template.id, exerciseID: item.exerciseID).map { prefs.weightUnit.fromKg($0) }
            }
        }
        .onChange(of: item) { _, newValue in
            guard let newValue else { return }
            var list = template.exercises
            if let index = list.firstIndex(where: { $0.id == newValue.id }) {
                list[index] = newValue
                template.exercises = list
            }
        }
        .onChange(of: startWeight) { _, newValue in
            guard let item else { return }
            TrainingTargetWeights.set(newValue.map { prefs.weightUnit.toKg($0) }, templateID: template.id, exerciseID: item.exerciseID)
        }
        .onDisappear { context.saveQuietly() }
    }

    private var itemBinding: Binding<TemplateExercise>? {
        guard item != nil else { return nil }
        return Binding(
            get: { item ?? TemplateExercise(exerciseID: "") },
            set: { item = $0 }
        )
    }
}
