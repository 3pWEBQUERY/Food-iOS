import SwiftUI
import SwiftData

/// Laufendes Training (Vollbild). Alle Eingaben werden sofort lokal gespeichert.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(WorkoutStore.self) private var workouts
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let session = workouts.activeSession(in: context) {
                WorkoutActiveContent(session: session)
            } else {
                ContentUnavailableView {
                    Label("Kein aktives Training", systemImage: "dumbbell")
                } description: {
                    Text("Starte ein Training im Tab „Training“.")
                } actions: {
                    Button("Schliessen") { router.isWorkoutPresented = false }
                        .buttonStyle(.glass)
                }
            }
        }
    }
}

// MARK: - Inhalt

private enum WorkoutPickerMode: Identifiable {
    case add
    case swap(ExerciseLog)

    var id: String {
        switch self {
        case .add: "add"
        case .swap(let log): "swap-\(log.id.uuidString)"
        }
    }
}

private struct WorkoutActiveContent: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(WorkoutStore.self) private var workouts
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs

    @Query private var allExercises: [Exercise]
    @Query private var allEquipment: [Equipment]

    @State private var pickerMode: WorkoutPickerMode?
    @State private var showFinish = false
    @State private var showDiscard = false
    @State private var notesVisible: Set<UUID> = []

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            ForEach(session.sortedExercises) { log in
                exerciseSection(log)
            }

            Section {
                Button {
                    pickerMode = .add
                } label: {
                    Label("Übung hinzufügen", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
            }

            Color.clear
                .frame(height: 80)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            WorkoutRestTimerPill()
                .padding(.bottom, Theme.Space.s)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.isWorkoutPresented = false
                } label: {
                    Label("Minimieren", systemImage: "chevron.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Training verwerfen", systemImage: "trash", role: .destructive) { showDiscard = true }
                } label: {
                    Label("Optionen", systemImage: "ellipsis")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Beenden") { showFinish = true }
                    .buttonStyle(.glassProminent)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { trainingHideKeyboard() }
            }
        }
        .sheet(item: $pickerMode) { mode in
            switch mode {
            case .add:
                TrainingExercisePicker(title: "Übung hinzufügen", suggested: []) { exercise in
                    workouts.addExercise(exercise, to: session, in: context)
                }
            case .swap(let log):
                let gym = TrainingQueries.activeGym(in: context)
                TrainingExercisePicker(title: "Übung tauschen",
                                       suggested: TrainingQueries.swapCandidates(for: log.exerciseID, all: allExercises, gym: gym)) { exercise in
                    workouts.swap(log, to: exercise, in: session, in: context)
                }
            }
        }
        .sheet(isPresented: $showFinish) {
            WorkoutFinishSheet(session: session)
        }
        .confirmationDialog("Training verwerfen?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                router.isWorkoutPresented = false
                workouts.discard(session, in: context)
            }
        } message: {
            Text("Alle Sätze dieser Einheit werden gelöscht.")
        }
        .sensoryFeedback(.success, trigger: workouts.restCompletionCount)
    }

    // MARK: Kopfbereich

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(Fmt.duration(timeline.date.timeIntervalSince(session.startedAt)))
                    .font(.metricLarge)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Trainingsdauer \(Fmt.minutes(timeline.date.timeIntervalSince(session.startedAt)))")
                HStack(spacing: Theme.Space.l) {
                    StatValue(value: "\(session.completedSetCount)", unit: "von \(session.exercises.reduce(0) { $0 + $1.sets.count })", label: "Sätze")
                    StatValue(value: Fmt.weight(session.volumeKg, unit: prefs.weightUnit, digits: 0), unit: prefs.weightUnit.symbol, label: "Volumen")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Übung

    @ViewBuilder
    private func exerciseSection(_ log: ExerciseLog) -> some View {
        let previous = TrainingQueries.lastLog(exerciseID: log.exerciseID, equipmentID: log.equipmentID,
                                               excluding: session.id, in: context)
        Section {
            let sets = log.sortedSets
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                let workingIndex = sets.prefix(index + 1).filter { $0.kind == .working }.count
                WorkoutSetRow(set: set, workingIndex: workingIndex, targetRange: TrainingMath.repRange(min: log.targetRepMin, max: log.targetRepMax),
                              unit: prefs.weightUnit) { completed in
                    handleCompletion(of: set, in: log, completed: completed)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        workouts.deleteSet(set, from: log, in: context)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Satzart", systemImage: "tag") {
                        let all = SetKind.allCases
                        let index = all.firstIndex(of: set.kind) ?? 0
                        set.kind = all[(index + 1) % all.count]
                    }
                    .tint(Theme.training)
                }
            }

            HStack(spacing: Theme.Space.xs) {
                addButton("Satz", systemImage: "plus") { workouts.addSet(to: log, kind: .working, in: context) }
                addButton("Aufwärmen", systemImage: "flame") { workouts.addSet(to: log, kind: .warmup, in: context) }
                addButton("Drop", systemImage: "arrow.down.right") { workouts.addSet(to: log, kind: .drop, in: context) }
            }
            .buttonStyle(.borderless)

            if notesVisible.contains(log.id) || !log.notes.isEmpty {
                WorkoutNotesField(log: log)
            }
        } header: {
            exerciseHeader(log)
        } footer: {
            exerciseFooter(log, previous: previous)
        }
    }

    private func addButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.fill, in: Capsule())
        }
        .foregroundStyle(.primary)
    }

    private func exerciseHeader(_ log: ExerciseLog) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            if let group = log.supersetGroup {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.training)
                    .frame(width: 4, height: 32)
                    .accessibilityHidden(true)
                    .help("Supersatz \(group)")
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(log.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let group = log.supersetGroup {
                        Badge(text: "Supersatz \(group)", tint: Theme.training)
                    }
                }
                if let label = log.equipmentLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            exerciseMenu(log)
        }
        .textCase(nil)
        .padding(.top, Theme.Space.xs)
    }

    private func exerciseMenu(_ log: ExerciseLog) -> some View {
        let options = allEquipment.filter { $0.exerciseIDs.contains(log.exerciseID) }
            .sorted { $0.displayName < $1.displayName }
        return Menu {
            Button("Übung tauschen", systemImage: "arrow.triangle.2.circlepath") { pickerMode = .swap(log) }
            Menu("Gerät", systemImage: "gearshape.2") {
                Button {
                    log.equipmentID = nil
                    log.equipmentLabel = nil
                } label: {
                    if log.equipmentID == nil { Label("Kein bestimmtes Gerät", systemImage: "checkmark") } else { Text("Kein bestimmtes Gerät") }
                }
                ForEach(options) { equipment in
                    Button {
                        log.equipmentID = equipment.id
                        log.equipmentLabel = equipment.displayName
                    } label: {
                        if log.equipmentID == equipment.id { Label(equipment.displayName, systemImage: "checkmark") } else { Text(equipment.displayName) }
                    }
                }
            }
            Menu("Pause: \(log.restSeconds) s", systemImage: "timer") {
                ForEach([45, 60, 90, 120, 150, 180, 240], id: \.self) { seconds in
                    Button("\(seconds) s") { log.restSeconds = seconds }
                }
            }
            supersetMenu(log)
            Button("Notiz", systemImage: "note.text") { notesVisible.insert(log.id) }
            Divider()
            Button("Übung entfernen", systemImage: "trash", role: .destructive) {
                workouts.removeExercise(log, from: session, in: context)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Optionen für \(log.exerciseName)")
    }

    @ViewBuilder
    private func supersetMenu(_ log: ExerciseLog) -> some View {
        let ordered = session.sortedExercises
        if let index = ordered.firstIndex(where: { $0.id == log.id }) {
            if log.supersetGroup != nil {
                Button("Supersatz auflösen", systemImage: "minus.circle") {
                    let group = log.supersetGroup
                    log.supersetGroup = nil
                    let remaining = ordered.filter { $0.supersetGroup == group && $0.id != log.id }
                    if remaining.count == 1 { remaining[0].supersetGroup = nil }
                }
            } else if index + 1 < ordered.count {
                Button("Supersatz mit nächster Übung", systemImage: "link") {
                    let next = ordered[index + 1]
                    let group = next.supersetGroup ?? ((ordered.compactMap(\.supersetGroup).max() ?? 0) + 1)
                    log.supersetGroup = group
                    next.supersetGroup = group
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseFooter(_ log: ExerciseLog, previous: ExerciseLog?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let previous, let date = previous.session?.startedAt {
                let summary = previous.sortedSets.filter { $0.kind != .warmup }
                    .map { TrainingMath.setLabel($0, unit: prefs.weightUnit) }
                    .joined(separator: ", ")
                Text("Zuletzt (\(Fmt.shortDate(date))): \(summary)")
            }
            if log.equipmentID != nil {
                Text("Gewichte werden pro Gerät ausgewertet – Werte verschiedener Maschinen sind nicht direkt vergleichbar.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Logik

    private func handleCompletion(of set: SetLog, in log: ExerciseLog, completed: Bool) {
        set.isCompleted = completed
        set.completedAt = completed ? .now : nil
        if completed && set.reps == 0, let target = set.targetReps ?? log.targetRepMax {
            set.reps = target
        }
        context.saveQuietly()
        guard completed, prefs.autoStartRestTimer, set.kind != .warmup || log.restSeconds > 0 else { return }

        // Im Supersatz erst nach der letzten Übung der Gruppe pausieren.
        let ordered = session.sortedExercises
        if let group = log.supersetGroup,
           let index = ordered.firstIndex(where: { $0.id == log.id }),
           index + 1 < ordered.count, ordered[index + 1].supersetGroup == group {
            return
        }
        let seconds = set.kind == .warmup ? min(60, log.restSeconds) : log.restSeconds
        let next = nextLabel(after: set, in: log)
        workouts.startRest(seconds: seconds, nextLabel: next)
    }

    private func nextLabel(after set: SetLog, in log: ExerciseLog) -> String? {
        if log.sortedSets.contains(where: { !$0.isCompleted }) { return log.exerciseName }
        let ordered = session.sortedExercises
        if let index = ordered.firstIndex(where: { $0.id == log.id }), index + 1 < ordered.count {
            return ordered[index + 1].exerciseName
        }
        return nil
    }
}

// MARK: - Satzzeile

private struct WorkoutSetRow: View {
    @Bindable var set: SetLog
    let workingIndex: Int
    let targetRange: String
    let unit: WeightUnit
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TrainingSetBadge(set: set, workingIndex: workingIndex)

            HStack(spacing: 4) {
                TrainingNumberInput(value: unit.fromKg(set.weightKg), placeholder: "0", fractionDigits: 2, width: 70) { value in
                    set.weightKg = unit.toKg(value)
                }
                .accessibilityLabel("Gewicht in \(unit.symbol)")
                Text(unit.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("×")
                .foregroundStyle(.tertiary)

            TrainingNumberInput(value: Double(set.reps), placeholder: targetRange, fractionDigits: 0, width: 56) { value in
                set.reps = max(0, Int(value))
            }
            .accessibilityLabel("Wiederholungen")

            TrainingEffortMenu(set: set)

            Spacer(minLength: 0)

            Button {
                onToggle(!set.isCompleted)
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Theme.training : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.impact(weight: .medium), trigger: set.isCompleted)
            .accessibilityLabel(set.isCompleted ? "Satz erledigt" : "Satz abhaken")
        }
        .opacity(set.isCompleted ? 0.75 : 1)
    }
}

private struct WorkoutNotesField: View {
    @Bindable var log: ExerciseLog

    var body: some View {
        TextField("Notiz zur Übung", text: $log.notes, axis: .vertical)
            .font(.subheadline)
            .lineLimit(1...4)
    }
}

// MARK: - Pausentimer

/// Schwebender Pausentimer im Liquid-Glass-Stil.
struct WorkoutRestTimerPill: View {
    @Environment(WorkoutStore.self) private var workouts

    var body: some View {
        if let end = workouts.restEndsAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let remaining = max(0, end.timeIntervalSince(timeline.date))
                let progress = workouts.restDuration > 0 ? remaining / workouts.restDuration : 0
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        GlassIconButton(systemImage: "minus", accessibilityLabel: "15 Sekunden weniger", size: 48) {
                            workouts.adjustRest(by: -15)
                        }
                        HStack(spacing: 10) {
                            RingMeter(progress: progress, tint: Theme.training, lineWidth: 3)
                                .frame(width: 22, height: 22)
                            Text(Fmt.duration(remaining.rounded(.up)))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .contentTransition(.numericText(countsDown: true))
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Pause")
                        .accessibilityValue("\(Int(remaining.rounded(.up))) Sekunden")
                        GlassIconButton(systemImage: "plus", accessibilityLabel: "15 Sekunden mehr", size: 48) {
                            workouts.adjustRest(by: 15)
                        }
                        GlassIconButton(systemImage: "forward.end.fill", accessibilityLabel: "Pause überspringen", size: 48) {
                            workouts.skipRest()
                        }
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: end) {
                let wait = end.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                workouts.restDidFinish(expectedEnd: end)
            }
        }
    }
}

// MARK: - Bottom Accessory

/// Kompakte Anzeige des laufenden Trainings über der Tab-Bar.
struct ActiveWorkoutAccessory: View {
    @Environment(WorkoutStore.self) private var workouts
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let session = workouts.activeSession(in: context)
        Button {
            router.isWorkoutPresented = true
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let resting = workouts.restEndsAt.map { $0 > timeline.date } ?? false
                HStack(spacing: 10) {
                    Image(systemName: resting ? "timer" : "dumbbell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.training)
                    if placement != .inline {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(currentExerciseName(session) ?? session?.name ?? "Training")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(resting ? "Pause" : (session?.name ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(resting ? Fmt.duration(workouts.restRemaining(at: timeline.date).rounded(.up))
                                 : Fmt.duration(timeline.date.timeIntervalSince(session?.startedAt ?? timeline.date)))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(resting ? Theme.training : .primary)
                }
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Laufendes Training öffnen")
    }

    private func currentExerciseName(_ session: WorkoutSession?) -> String? {
        session?.sortedExercises.first { log in log.sets.contains { !$0.isCompleted } }?.exerciseName
    }
}

// MARK: - Abschluss

private struct WorkoutFinishSheet: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutStore.self) private var workouts
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs

    @State private var exertion: Int? = nil
    @State private var dayForm: Int? = nil
    @State private var notes = ""

    private let dayFormLabels = ["Sehr schwach", "Schwach", "Normal", "Gut", "Sehr gut"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Space.l) {
                        StatValue(value: Fmt.minutes(session.duration), label: "Dauer")
                        StatValue(value: "\(session.completedSetCount)", label: "Sätze")
                        StatValue(value: Fmt.weight(session.volumeKg, unit: prefs.weightUnit, digits: 0), unit: prefs.weightUnit.symbol, label: "Volumen")
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(1...10, id: \.self) { value in
                            ChoiceChip(title: "\(value)", isSelected: exertion == value) {
                                exertion = exertion == value ? nil : value
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Wie anstrengend war das Training?")
                } footer: {
                    Text("1 = sehr leicht, 10 = maximal. Hilft bei Vorschlägen zur Regeneration.")
                }

                Section("Tagesform") {
                    FlowLayout(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            ChoiceChip(title: dayFormLabels[value - 1], isSelected: dayForm == value) {
                                dayForm = dayForm == value ? nil : value
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Notizen") {
                    TextField("Wie lief es? Besonderheiten?", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if session.exercises.contains(where: { $0.sets.contains { !$0.isCompleted } }) {
                    Section {
                        InfoNote(text: "Nicht abgehakte Sätze werden nicht gespeichert.")
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Training beenden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zurück", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .buttonStyle(.glassProminent)
                }
            }
            .onAppear { notes = session.notes }
        }
        .presentationDetents([.large])
    }

    private func save() {
        workouts.finish(session, exertion: exertion, dayForm: dayForm, notes: notes, in: context)
        dismiss()
        router.isWorkoutPresented = false
    }
}
