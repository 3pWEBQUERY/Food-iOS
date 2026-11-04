import SwiftUI
import SwiftData

/// Trainingsverlauf mit Monatskalender und Gruppierung nach Kalenderwoche.
struct WorkoutHistoryView: View {
    @Environment(AppPreferences.self) private var prefs
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted == true }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var month: Date = .now

    private var weeks: [(start: Date, sessions: [WorkoutSession])] {
        let grouped = Dictionary(grouping: sessions) { TrainingQueries.weekStart(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { (start: $0, sessions: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                WorkoutMonthCalendar(month: $month, sessions: sessions)
            }

            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Trainings", systemImage: "dumbbell")
                } description: {
                    Text("Abgeschlossene Trainings erscheinen hier – auch ohne Internetverbindung.")
                }
                .listRowBackground(Color.clear)
            }

            ForEach(weeks, id: \.start) { week in
                Section {
                    ForEach(week.sessions) { session in
                        NavigationLink(value: AppDestination.workoutSession(id: session.id)) {
                            WorkoutHistoryRow(session: session, unit: prefs.weightUnit)
                        }
                    }
                } header: {
                    weekHeader(week.start, sessions: week.sessions)
                }
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .navigationTitle("Verlauf")
    }

    private func weekHeader(_ start: Date, sessions: [WorkoutSession]) -> some View {
        let cal = TrainingQueries.calendar
        let week = cal.component(.weekOfYear, from: start)
        let volume = sessions.reduce(0) { $0 + $1.volumeKg }
        return HStack {
            Text("KW \(week) · \(Fmt.shortDate(start))")
            Spacer()
            Text("\(sessions.count) × · \(Fmt.weightWithUnit(volume, unit: prefs.weightUnit, digits: 0))")
                .monospacedDigit()
        }
    }
}

private struct WorkoutHistoryRow: View {
    let session: WorkoutSession
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(Fmt.day(session.startedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("\(Fmt.minutes(session.duration)) · \(session.completedSetCount) Sätze · \(Fmt.weightWithUnit(session.volumeKg, unit: unit, digits: 0))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            if let rpe = session.perceivedExertion {
                Text("Belastung \(rpe)/10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Monatskalender mit markierten Trainingstagen.
struct WorkoutMonthCalendar: View {
    @Binding var month: Date
    let sessions: [WorkoutSession]

    var body: some View {
        let cal = TrainingQueries.calendar
        let interval = cal.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 86_400 * 30)
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let trained = Set(sessions.map { DayKey.make($0.startedAt) })
        let symbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let count = sessions.filter { interval.contains($0.startedAt) }.count

        VStack(spacing: Theme.Space.s) {
            HStack {
                Button {
                    month = cal.date(byAdding: .month, value: -1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Vorheriger Monat")
                Spacer()
                VStack(spacing: 0) {
                    Text(month.formatted(.dateTime.month(.wide).year().locale(Fmt.locale)))
                        .font(.headline)
                    Text(count == 1 ? "1 Training" : "\(count) Trainings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    month = cal.date(byAdding: .month, value: 1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(cal.isDate(month, equalTo: .now, toGranularity: .month))
                .accessibilityLabel("Nächster Monat")
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2Strong)
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { index in
                    Color.clear.frame(height: 32).id("lead-\(index)")
                }
                ForEach(0..<dayCount, id: \.self) { offset in
                    let day = cal.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
                    let isTrained = trained.contains(DayKey.make(day))
                    let isToday = cal.isDateInToday(day)
                    Text("\(offset + 1)")
                        .font(.footnote.monospacedDigit().weight(isToday ? .bold : .regular))
                        .foregroundStyle(isTrained ? Color.white : (isToday ? Theme.training : Color.primary))
                        .frame(width: 32, height: 32)
                        .background(isTrained ? Theme.training : Color.clear, in: Circle())
                        .accessibilityLabel(day.formatted(.dateTime.day().month(.wide).locale(Fmt.locale)))
                        .accessibilityValue(isTrained ? "Trainiert" : "")
                }
            }
        }
        .padding(.vertical, Theme.Space.xxs)
    }
}

// MARK: - Detail

/// Detail einer absolvierten Einheit – nachträglich bearbeitbar.
struct WorkoutSessionDetailView: View {
    let sessionID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Query private var matches: [WorkoutSession]

    @State private var isEditing = false
    @State private var showDelete = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
        let id = sessionID
        _matches = Query(filter: #Predicate<WorkoutSession> { $0.id == id })
    }

    var body: some View {
        Group {
            if let session = matches.first {
                WorkoutSessionDetailContent(session: session, isEditing: isEditing, unit: prefs.weightUnit)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: TrainingExport.text(for: session, unit: prefs.weightUnit)) {
                                Label("Teilen", systemImage: "square.and.arrow.up")
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(isEditing ? "Fertig" : "Bearbeiten") {
                                if isEditing {
                                    AuditLog.record(context, actor: .user, summary: "Training bearbeitet: \(session.name)",
                                                    entityType: EntityType.workout, entityID: session.id.uuidString)
                                    context.saveQuietly()
                                }
                                withAnimation(.smooth) { isEditing.toggle() }
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if isEditing {
                            Button("Training löschen", role: .destructive) { showDelete = true }
                                .buttonStyle(.glass)
                                .padding(.bottom, Theme.Space.s)
                        }
                    }
                    .confirmationDialog("Training löschen?", isPresented: $showDelete, titleVisibility: .visible) {
                        Button("Löschen", role: .destructive) {
                            AuditLog.record(context, actor: .user, summary: "Training gelöscht: \(session.name)",
                                            entityType: EntityType.workout, entityID: session.id.uuidString)
                            context.delete(session)
                            context.saveQuietly()
                            dismiss()
                        }
                    } message: {
                        Text("Diese Einheit wird endgültig aus deinem Verlauf entfernt.")
                    }
                    .navigationTitle(session.name)
            } else {
                ContentUnavailableView("Training nicht gefunden", systemImage: "questionmark.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkoutSessionDetailContent: View {
    @Bindable var session: WorkoutSession
    let isEditing: Bool
    let unit: WeightUnit

    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                if isEditing {
                    TextField("Name", text: $session.name)
                    DatePicker("Beginn", selection: $session.startedAt)
                    Stepper(value: durationMinutes, in: 1...600, step: 5) {
                        LabeledContent("Dauer", value: "\(durationMinutes.wrappedValue) min")
                    }
                } else {
                    HStack(spacing: Theme.Space.l) {
                        StatValue(value: Fmt.minutes(session.duration), label: "Dauer")
                        StatValue(value: "\(session.completedSetCount)", label: "Sätze")
                        StatValue(value: Fmt.weight(session.volumeKg, unit: unit, digits: 0), unit: unit.symbol, label: "Volumen")
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Datum", value: "\(Fmt.mediumDate(session.startedAt)), \(Fmt.time(session.startedAt))")
                }
                Picker("Belastung", selection: $session.perceivedExertion) {
                    Text("Keine Angabe").tag(Int?.none)
                    ForEach(1...10, id: \.self) { Text("\($0) / 10").tag(Int?.some($0)) }
                }
                .disabled(!isEditing)
                Picker("Tagesform", selection: $session.dayForm) {
                    Text("Keine Angabe").tag(Int?.none)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag(Int?.some($0)) }
                }
                .disabled(!isEditing)
            }

            ForEach(session.sortedExercises) { log in
                Section {
                    let sets = log.sortedSets
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                        let workingIndex = sets.prefix(index + 1).filter { $0.kind == .working }.count
                        WorkoutHistorySetRow(set: set, workingIndex: workingIndex, unit: unit, isEditing: isEditing)
                            .swipeActions {
                                if isEditing {
                                    Button("Löschen", systemImage: "trash", role: .destructive) {
                                        log.sets.removeAll { $0.id == set.id }
                                        context.delete(set)
                                        context.saveQuietly()
                                    }
                                }
                            }
                    }
                    if isEditing {
                        Button("Satz hinzufügen", systemImage: "plus") {
                            let last = sets.last
                            let set = SetLog(order: (last?.order ?? -1) + 1, kind: .working,
                                             weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 0)
                            set.isCompleted = true
                            set.completedAt = session.startedAt
                            log.sets.append(set)
                            context.saveQuietly()
                        }
                        TextField("Notiz", text: Bindable(log).notes, axis: .vertical)
                    } else if !log.notes.isEmpty {
                        Text(log.notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let label = log.equipmentLabel {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .textCase(nil)
                }
            }

            Section("Notizen") {
                if isEditing {
                    TextField("Notizen zum Training", text: $session.notes, axis: .vertical)
                        .lineLimit(2...6)
                } else {
                    Text(session.notes.isEmpty ? "Keine Notizen" : session.notes)
                        .foregroundStyle(session.notes.isEmpty ? .secondary : .primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
    }

    private var durationMinutes: Binding<Int> {
        Binding(
            get: { max(1, Int((session.duration / 60).rounded())) },
            set: { session.endedAt = session.startedAt.addingTimeInterval(TimeInterval($0 * 60)) }
        )
    }
}

private struct WorkoutHistorySetRow: View {
    @Bindable var set: SetLog
    let workingIndex: Int
    let unit: WeightUnit
    let isEditing: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TrainingSetBadge(set: set, workingIndex: workingIndex)
            if isEditing {
                TrainingNumberInput(value: unit.fromKg(set.weightKg), placeholder: "0", fractionDigits: 2, width: 70) {
                    set.weightKg = unit.toKg($0)
                }
                Text(unit.symbol).font(.caption).foregroundStyle(.secondary)
                Text("×").foregroundStyle(.tertiary)
                TrainingNumberInput(value: Double(set.reps), placeholder: "0", fractionDigits: 0, width: 56) {
                    set.reps = max(0, Int($0))
                }
                TrainingEffortMenu(set: set)
            } else {
                Text(TrainingMath.setLabel(set, unit: unit))
                    .font(.body.monospacedDigit())
                Spacer()
                if let rir = set.rir {
                    Text("RIR \(rir)").font(.caption).foregroundStyle(.secondary)
                } else if let rpe = set.rpe {
                    Text("RPE \(Fmt.decimal(rpe))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
