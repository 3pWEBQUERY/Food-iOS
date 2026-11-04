import SwiftUI
import SwiftData
import Charts

/// Detailansicht einer Übung: Ausführung, Rekorde pro Gerätevariante, Verlauf.
struct ExerciseDetailView: View {
    let exerciseID: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Query private var matches: [Exercise]
    @Query private var logs: [ExerciseLog]
    @Query private var allExercises: [Exercise]
    @Query private var allEquipment: [Equipment]

    @State private var variant: String = WorkoutVariant.none
    @State private var showEquipmentEditor = false
    @State private var showDelete = false

    init(exerciseID: String) {
        self.exerciseID = exerciseID
        let id = exerciseID
        _matches = Query(filter: #Predicate<Exercise> { $0.id == id })
        _logs = Query(filter: #Predicate<ExerciseLog> { $0.exerciseID == id })
    }

    private var exercise: Exercise? { matches.first }

    /// Abgeschlossene Logs, älteste zuerst.
    private var completedLogs: [ExerciseLog] {
        logs.filter { $0.session?.isCompleted == true && $0.sets.contains { $0.isCompleted } }
            .sorted { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }

    private var variants: [(key: String, label: String)] {
        var seen: [String: String] = [:]
        for log in completedLogs {
            let key = log.equipmentID ?? WorkoutVariant.none
            seen[key] = log.equipmentLabel ?? "Ohne bestimmtes Gerät"
        }
        return seen.map { (key: $0.key, label: $0.value) }.sorted { $0.label < $1.label }
    }

    private var variantLogs: [ExerciseLog] {
        completedLogs.filter { ($0.equipmentID ?? WorkoutVariant.none) == variant }
    }

    var body: some View {
        Group {
            if let exercise {
                content(exercise)
            } else {
                ContentUnavailableView("Übung nicht gefunden", systemImage: "questionmark.circle")
            }
        }
        .screenBackground()
        .navigationTitle(exercise?.name ?? "Übung")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let exercise {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exercise.isFavorite.toggle()
                        context.saveQuietly()
                    } label: {
                        Label("Favorit", systemImage: exercise.isFavorite ? "star.fill" : "star")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Gerät hinzufügen", systemImage: "gearshape.2") { showEquipmentEditor = true }
                        if exercise.isCustom {
                            Button("Übung löschen", systemImage: "trash", role: .destructive) { showDelete = true }
                        }
                    } label: {
                        Label("Mehr", systemImage: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showEquipmentEditor) {
            TrainingEquipmentEditor(preselectedExerciseID: exerciseID)
        }
        .confirmationDialog("Übung löschen?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let exercise { context.delete(exercise) }
                context.saveQuietly()
                dismiss()
            }
        } message: {
            Text("Bereits erfasste Sätze bleiben im Verlauf erhalten.")
        }
        .onAppear {
            if !variants.contains(where: { $0.key == variant }), let last = completedLogs.last {
                variant = last.equipmentID ?? WorkoutVariant.none
            }
        }
    }

    private func content(_ exercise: Exercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                overview(exercise)
                if !exercise.instructions.isEmpty || !exercise.cues.isEmpty {
                    instructions(exercise)
                }
                if !completedLogs.isEmpty {
                    if variants.count > 1 {
                        Picker("Gerät", selection: $variant) {
                            ForEach(variants, id: \.key) { item in
                                Text(item.label).tag(item.key)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.training)
                    }
                    records
                    chart
                    recent
                } else {
                    Card {
                        CardHeader(title: "Rekorde & Verlauf", symbol: "trophy", tint: Theme.training)
                        Text("Sobald du diese Übung trainierst, erscheinen hier deine Bestwerte und der Verlauf.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                alternatives(exercise)
                machines(exercise)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.Space.xl)
        }
    }

    private func overview(_ exercise: Exercise) -> some View {
        Card {
            FlowLayout(spacing: 6) {
                Badge(text: exercise.primaryMuscle.title, tint: Theme.training)
                ForEach(exercise.secondaryMuscles) { muscle in
                    Badge(text: muscle.title)
                }
            }
            HStack(spacing: Theme.Space.l) {
                StatValue(value: exercise.category.title, label: "Typ", valueFont: .subheadline.weight(.semibold))
                StatValue(value: exercise.equipmentKind.title, label: "Equipment", valueFont: .subheadline.weight(.semibold))
                StatValue(value: exercise.difficulty.title, label: "Niveau", valueFont: .subheadline.weight(.semibold))
            }
            if exercise.isJointFriendly {
                Label("Gelenkschonende Variante", systemImage: "hand.raised")
                    .font(.footnote)
                    .foregroundStyle(Theme.positive)
            }
        }
    }

    private func instructions(_ exercise: Exercise) -> some View {
        Card {
            CardHeader(title: "Ausführung", symbol: "text.alignleft")
            if !exercise.instructions.isEmpty {
                Text(exercise.instructions)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !exercise.cues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(exercise.cues, id: \.self) { cue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.training).frame(width: 5, height: 5)
                            Text(cue).font(.subheadline)
                        }
                    }
                }
            }
            InfoNote(text: "Bei Schmerzen die Übung abbrechen. Kern ersetzt keine fachliche Anleitung.")
        }
    }

    private var records: some View {
        let working = variantLogs.flatMap { $0.sets.filter { $0.isCompleted && $0.kind != .warmup } }
        let bestE1RM = working.filter { $0.weightKg > 0 }.map(\.estimatedOneRepMax).max()
        let bestWeight = working.map(\.weightKg).max()
        let bestReps = working.map(\.reps).max()
        let bestVolume = variantLogs.map(\.volumeKg).max()
        return Card {
            CardHeader(title: "Persönliche Rekorde", symbol: "trophy", tint: Theme.training)
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.s) {
                GridRow {
                    StatValue(value: bestE1RM.map { Fmt.weight($0, unit: prefs.weightUnit) } ?? "–", unit: prefs.weightUnit.symbol, label: "Geschätztes 1RM")
                    StatValue(value: bestWeight.map { Fmt.weight($0, unit: prefs.weightUnit) } ?? "–", unit: prefs.weightUnit.symbol, label: "Höchstes Gewicht")
                }
                GridRow {
                    StatValue(value: bestReps.map { "\($0)" } ?? "–", unit: "Wdh.", label: "Meiste Wiederholungen")
                    StatValue(value: bestVolume.map { Fmt.weight($0, unit: prefs.weightUnit, digits: 0) } ?? "–", unit: prefs.weightUnit.symbol, label: "Bestes Volumen")
                }
            }
            Text("1RM nach Epley geschätzt – bei mehr als 12 Wiederholungen nur grob aussagekräftig.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        let points: [(date: Date, value: Double)] = variantLogs.compactMap { log in
            guard let date = log.session?.startedAt, let value = log.bestEstimatedOneRepMax else { return nil }
            return (date, prefs.weightUnit.fromKg(value))
        }
        return Card {
            CardHeader(title: "Verlauf geschätztes 1RM", symbol: "chart.line.uptrend.xyaxis", tint: Theme.training)
            if points.count < 2 {
                Text("Mindestens zwei Einheiten nötig.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Datum", point.date), y: .value("1RM", point.value))
                            .foregroundStyle(Theme.training)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Datum", point.date), y: .value("1RM", point.value))
                            .foregroundStyle(Theme.training)
                            .symbolSize(24)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Fmt.locale))
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Verlauf des geschätzten 1RM")
                .accessibilityValue("Von \(Fmt.decimal(points.first?.value ?? 0)) auf \(Fmt.decimal(points.last?.value ?? 0)) \(prefs.weightUnit.symbol)")
            }
        }
    }

    private var recent: some View {
        Card {
            CardHeader(title: "Letzte Einheiten", symbol: "clock")
            ForEach(Array(variantLogs.reversed().prefix(5))) { log in
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.session.map { Fmt.mediumDate($0.startedAt) } ?? "")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(log.sortedSets.filter(\.isCompleted).map { set in
                        (set.kind == .working ? "" : "\(set.kind.shortLabel) ") + TrainingMath.setLabel(set, unit: prefs.weightUnit)
                    }.joined(separator: " · "))
                    .font(.subheadline.monospacedDigit())
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func alternatives(_ exercise: Exercise) -> some View {
        let items = exercise.alternativeIDs.compactMap { id in allExercises.first { $0.id == id } }
        if !items.isEmpty {
            Card(padding: 0) {
                CardHeader(title: "Alternativen", symbol: "arrow.triangle.2.circlepath")
                    .padding([.horizontal, .top], Theme.Space.m)
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        NavigationLink(value: AppDestination.exercise(id: item.id)) {
                            HStack {
                                TrainingExerciseRow(exercise: item)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, Theme.Space.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, Theme.Space.s)
            }
        }
    }

    @ViewBuilder
    private func machines(_ exercise: Exercise) -> some View {
        let items = allEquipment.filter { $0.exerciseIDs.contains(exercise.id) }.sorted { $0.displayName < $1.displayName }
        if !items.isEmpty {
            Card {
                CardHeader(title: "Geräte", symbol: "gearshape.2")
                ForEach(items) { item in
                    HStack {
                        Text(item.displayName).font(.subheadline)
                        Spacer()
                        if item.isCustom { Badge(text: "Eigenes") }
                    }
                }
            }
        }
    }
}

enum WorkoutVariant {
    static let none = "__none__"
}
