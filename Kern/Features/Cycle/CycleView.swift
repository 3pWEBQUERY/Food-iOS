import SwiftUI
import SwiftData
import Charts

/// Optionales Zyklusmodul. Besonders geschützte Daten, lokal gespeichert, keine Diagnosen.
struct CycleView: View {
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        Group {
            if prefs.isEnabled(.cycle) {
                ProgressSensitiveGate(isRequired: prefs.lockSensitiveModules, reason: "Entsperre dein Zyklusmodul.") {
                    CycleContent()
                }
            } else {
                ContentUnavailableView {
                    Label("Zyklustracking ist deaktiviert", systemImage: "circle.dashed")
                } description: {
                    Text("Das Modul ist freiwillig. Deine Daten bleiben auf diesem Gerät und werden besonders geschützt.")
                } actions: {
                    Button("Modul aktivieren") { prefs.setModule(.cycle, enabled: true) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Zyklus")
    }
}

private struct CycleEditTarget: Identifiable {
    let date: Date
    var id: String { DayKey.make(date) }
}

private struct CycleContent: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \CycleDay.date) private var days: [CycleDay]
    @Query private var profiles: [UserProfile]

    @AppStorage("kern.cycle.reminder") private var reminderEnabled = false
    @State private var month: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var editing: CycleEditTarget?

    private var stats: CycleStats { CycleCalculator.stats(days, defaultLength: prefs.cycleLengthDays) }
    private var byKey: [String: CycleDay] { Dictionary(days.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        let stats = self.stats
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                statusCard(stats)
                calendarCard(stats)
                statsCard(stats)
                correlationCard(stats)
                settingsCard(stats)

                InfoNote(text: "Zyklusdaten werden besonders geschützt, nur auf diesem Gerät gespeichert und nur mit deiner ausdrücklichen Zustimmung für Auswertungen genutzt. Kern stellt keine Diagnosen. Schätzungen eignen sich nicht zur Verhütung.",
                         symbol: "lock.shield")
                if profiles.first?.specialSituation == .pregnant || profiles.first?.specialSituation == .breastfeeding {
                    InfoNote(text: "Du hast eine Schwangerschaft oder Stillzeit angegeben. Zyklusschätzungen sind in dieser Zeit nicht aussagekräftig.",
                             symbol: "info.circle", tint: Theme.warning)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = CycleEditTarget(date: .now) } label: {
                    Label("Heute erfassen", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            CycleDayEditor(date: target.date)
                .presentationDetents([.large])
        }
        .onChange(of: stats.nextPeriodEstimate) { _, _ in
            CycleCalculator.updateReminder(enabled: reminderEnabled, stats: self.stats)
        }
    }

    // MARK: Status

    private func statusCard(_ stats: CycleStats) -> some View {
        Card {
            CardHeader(title: "Heute", symbol: "circle.dashed", tint: Theme.cycle)
            if let day = stats.currentCycleDay {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Zyklustag")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("\(day)")
                        .font(.metricMedium)
                        .monospacedDigit()
                }
                if let until = stats.daysUntilNextPeriod() {
                    Text(until > 0
                         ? "Nächste Periode in etwa \(until) Tag\(until == 1 ? "" : "en") · Schätzung"
                         : until == 0 ? "Periode heute erwartet · Schätzung"
                         : "Erwarteter Beginn war vor \(-until) Tag\(until == -1 ? "" : "en") · Schätzung")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Erfasse den Beginn deiner Periode, damit Kern Zyklustage und Längen darstellen kann.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                editing = CycleEditTarget(date: .now)
            } label: {
                Label(byKey[DayKey.today] == nil ? "Heute erfassen" : "Heutigen Eintrag bearbeiten", systemImage: "square.and.pencil")
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: Kalender

    private func calendarCard(_ stats: CycleStats) -> some View {
        let cal = Calendar.current
        let predicted = CycleCalculator.predictedDays(stats: stats, periodLength: prefs.periodLengthDays)
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let weekdayOfFirst = cal.component(.weekday, from: month)
        let leading = (weekdayOfFirst - 2 + 7) % 7   // Woche beginnt am Montag
        let cells: [Date?] = Array(repeating: nil, count: leading) + (0..<daysInMonth).map { month.adding(days: $0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let lookup = byKey

        return Card {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Vorheriger Monat")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year().locale(Fmt.locale)))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Nächster Monat")
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { name in
                    Text(name)
                        .font(.caption2Strong)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = DayKey.make(date)
                        CycleDayCell(date: date, entry: lookup[key], isPredicted: predicted.contains(key) && lookup[key]?.flow.isBleeding != true)
                            .onTapGesture {
                                if date <= .now { editing = CycleEditTarget(date: date) }
                            }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            HStack(spacing: Theme.Space.m) {
                legend(fill: true, "Periode")
                legend(fill: false, "Geschätzt")
                HStack(spacing: 4) {
                    Circle().fill(Color.secondary).frame(width: 4, height: 4)
                    Text("Notiz/Symptom").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func legend(fill: Bool, _ title: String) -> some View {
        HStack(spacing: 4) {
            if fill {
                Circle().fill(Theme.cycle.opacity(0.6)).frame(width: 10, height: 10)
            } else {
                Circle().strokeBorder(Theme.cycle.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])).frame(width: 10, height: 10)
            }
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let new = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.snappy) { month = new }
        }
    }

    // MARK: Statistik

    private func statsCard(_ stats: CycleStats) -> some View {
        Card {
            CardHeader(title: "Zykluslänge", symbol: "arrow.triangle.2.circlepath", tint: Theme.cycle)
            HStack(alignment: .top) {
                StatValue(value: stats.averageLength.map { Fmt.decimal($0) } ?? "–", unit: stats.averageLength == nil ? nil : "Tage",
                          label: "Durchschnitt")
                Spacer()
                StatValue(value: stats.lastLength.map { "\($0)" } ?? "–", unit: stats.lastLength == nil ? nil : "Tage",
                          label: "Letzter Zyklus")
                Spacer()
                StatValue(value: "\(stats.periodStarts.count)", label: "Erfasste Perioden")
            }
            if stats.usesDefaultLength {
                Text("Für die Schätzung wird deine angegebene Zykluslänge von \(prefs.cycleLengthDays) Tagen verwendet, bis mindestens zwei Perioden erfasst sind.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Zusammenhänge

    @ViewBuilder
    private func correlationCard(_ stats: CycleStats) -> some View {
        @Bindable var prefs = prefs
        Card {
            CardHeader(title: "Zeitliche Zusammenhänge", symbol: "point.3.connected.trianglepath.dotted", tint: Theme.cycle)
            if !prefs.cycleAnalysisConsent {
                Text("Mit deiner Zustimmung stellt Kern Gewichtsschwankungen und Trainingsbelastung entlang deiner Zyklustage dar. Die Auswertung erfolgt ausschliesslich auf diesem Gerät.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle("Zyklusdaten für Auswertungen verwenden", isOn: $prefs.cycleAnalysisConsent)
                    .tint(Theme.cycle)
            } else if stats.periodStarts.isEmpty {
                Text("Sobald ein Periodenbeginn erfasst ist, erscheinen hier deine Verläufe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                CycleCorrelationCharts(starts: stats.periodStarts)
                Toggle("Zustimmung zur Auswertung", isOn: $prefs.cycleAnalysisConsent)
                    .font(.footnote)
                    .tint(Theme.cycle)
            }
        }
    }

    // MARK: Einstellungen

    private func settingsCard(_ stats: CycleStats) -> some View {
        @Bindable var prefs = prefs
        return Card {
            CardHeader(title: "Einstellungen", symbol: "gearshape")
            Stepper(value: $prefs.cycleLengthDays, in: 20...45) {
                LabeledContent("Übliche Zykluslänge", value: "\(prefs.cycleLengthDays) Tage")
            }
            Stepper(value: $prefs.periodLengthDays, in: 2...10) {
                LabeledContent("Übliche Periodendauer", value: "\(prefs.periodLengthDays) Tage")
            }
            Toggle("Erinnerung vor erwartetem Beginn", isOn: $reminderEnabled)
                .tint(Theme.cycle)
                .onChange(of: reminderEnabled) { _, enabled in
                    CycleCalculator.updateReminder(enabled: enabled, stats: stats)
                }
            Text("Die Mitteilung enthält keine sensiblen Details.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Kalenderzelle

private struct CycleDayCell: View {
    let date: Date
    let entry: CycleDay?
    let isPredicted: Bool

    private var flowOpacity: Double {
        switch entry?.flow ?? CycleFlow.none {
        case .light: 0.35
        case .medium: 0.6
        case .heavy: 0.9
        default: 0
        }
    }

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isFuture = date > .now
        let hasDetails = entry.map { !$0.symptomsRaw.isEmpty || !$0.note.isEmpty || $0.energy > 0 || $0.mood > 0 } ?? false
        VStack(spacing: 2) {
            ZStack {
                if flowOpacity > 0 {
                    Circle().fill(Theme.cycle.opacity(flowOpacity))
                } else if isPredicted {
                    Circle().strokeBorder(Theme.cycle.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
                if isToday {
                    Circle().strokeBorder(Theme.accent, lineWidth: 2)
                }
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(flowOpacity > 0.5 ? Color.white : (isFuture ? Color.secondary : Color.primary))
                if entry?.flow == .spotting {
                    Circle().fill(Theme.cycle).frame(width: 5, height: 5).offset(y: 12)
                }
            }
            .frame(width: 36, height: 36)
            Circle()
                .fill(hasDetails ? Color.secondary : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isFuture ? [] : .isButton)
    }

    private var accessibilityText: String {
        var parts = [Fmt.mediumDate(date)]
        if let entry, entry.flow != CycleFlow.none { parts.append("Blutung \(entry.flow.title)") }
        if isPredicted { parts.append("geschätzte Periode") }
        if let entry, !entry.symptoms.isEmpty { parts.append(entry.symptoms.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Tageseintrag

struct CycleDayEditor: View {
    let date: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var flow: CycleFlow = .none
    @State private var symptoms: Set<CycleSymptom> = []
    @State private var energy = 0
    @State private var mood = 0
    @State private var exertion = 0
    @State private var note = ""
    @State private var existing: CycleDay?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Blutung") {
                    FlowLayout(spacing: 8) {
                        ForEach(CycleFlow.allCases) { option in
                            ChoiceChip(title: option.title, isSelected: flow == option) { flow = option }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Beschwerden & Symptome") {
                    FlowLayout(spacing: 8) {
                        ForEach(CycleSymptom.allCases) { symptom in
                            ChoiceChip(title: symptom.title, isSelected: symptoms.contains(symptom)) {
                                if symptoms.contains(symptom) { symptoms.remove(symptom) } else { symptoms.insert(symptom) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    CycleRatingRow(title: "Energie", value: $energy)
                    CycleRatingRow(title: "Wohlbefinden", value: $mood)
                    CycleRatingRow(title: "Belastungsempfinden", value: $exertion)
                } header: {
                    Text("Tagesform")
                } footer: {
                    Text("1 = sehr niedrig, 5 = sehr hoch. Erneut tippen entfernt die Angabe.")
                }
                Section("Notiz") {
                    TextField("Persönliche Notiz", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                if existing != nil {
                    Section {
                        Button("Eintrag löschen", role: .destructive, action: deleteEntry)
                    }
                }
            }
            .navigationTitle(Fmt.day(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let entry = CycleCalculator.day(for: date, in: context) else { return }
        existing = entry
        flow = entry.flow
        symptoms = Set(entry.symptoms)
        energy = entry.energy
        mood = entry.mood
        exertion = entry.exertionCapacity
        note = entry.note
    }

    private func save() {
        let entry = existing ?? {
            let new = CycleDay(date: date)
            context.insert(new)
            return new
        }()
        entry.flow = flow
        entry.symptoms = CycleSymptom.allCases.filter { symptoms.contains($0) }
        entry.energy = energy
        entry.mood = mood
        entry.exertionCapacity = exertion
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        AuditLog.record(context, actor: .user, summary: existing == nil ? "Zykluseintrag erstellt" : "Zykluseintrag bearbeitet",
                        entityType: EntityType.cycle, entityID: entry.id.uuidString)
        context.saveQuietly()
        dismiss()
    }

    private func deleteEntry() {
        guard let existing else { return }
        AuditLog.record(context, actor: .user, summary: "Zykluseintrag gelöscht", entityType: EntityType.cycle,
                        entityID: existing.id.uuidString)
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            context.delete(existing)
            context.saveQuietly()
        }
    }
}

private struct CycleRatingRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        value = value == level ? 0 : level
                    } label: {
                        Circle()
                            .fill(level <= value ? Theme.cycle : Theme.fill)
                            .frame(width: 22, height: 22)
                            .frame(width: 30, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(level) von 5")
                    .accessibilityAddTraits(value == level ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}

// MARK: - Zusammenhänge

/// Beschreibende Darstellung entlang der Zyklustage – keine Ursachen, keine Diagnosen.
private struct CycleCorrelationCharts: View {
    let starts: [Date]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    private struct Point: Identifiable {
        var id: Int { day }
        let day: Int
        let value: Double
        let count: Int
    }

    /// Abweichung vom Zyklus-Mittelwert des Gewichts je Zyklustag.
    private var weightPoints: [Point] {
        guard let first = starts.first else { return [] }
        var byCycle: [Int: [(day: Int, kg: Double)]] = [:]
        for w in weights where w.date >= first {
            guard let index = starts.lastIndex(where: { $0 <= w.date.startOfDay }),
                  let day = CycleCalculator.cycleDay(for: w.date, starts: starts) else { continue }
            byCycle[index, default: []].append((day, w.kg))
        }
        var buckets: [Int: [Double]] = [:]
        for (_, values) in byCycle where values.count >= 3 {
            let mean = values.map(\.kg).reduce(0, +) / Double(values.count)
            for v in values { buckets[v.day, default: []].append(v.kg - mean) }
        }
        return buckets.map { Point(day: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.day < $1.day }
    }

    private var exertionPoints: [Point] {
        var buckets: [Int: [Double]] = [:]
        for s in sessions {
            guard let rpe = s.perceivedExertion, let day = CycleCalculator.cycleDay(for: s.startedAt, starts: starts) else { continue }
            buckets[day, default: []].append(Double(rpe))
        }
        return buckets.map { Point(day: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        let weight = weightPoints
        let exertion = exertionPoints
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gewicht: Abweichung vom Zyklus-Mittel")
                    .font(.footnote.weight(.semibold))
                if weight.count >= 3 {
                    Chart(weight) { p in
                        BarMark(x: .value("Zyklustag", p.day), y: .value("Abweichung (kg)", p.value))
                            .foregroundStyle(Theme.cycle.opacity(0.75))
                    }
                    .chartXAxisLabel("Zyklustag")
                    .frame(height: 140)
                    .accessibilityLabel("Gewichtsabweichung nach Zyklustag")
                } else {
                    Text("Zu wenige Daten – es braucht mindestens drei Wägungen pro Zyklus.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Trainingsbelastung (Session-RPE)")
                    .font(.footnote.weight(.semibold))
                if exertion.count >= 3 {
                    Chart(exertion) { p in
                        PointMark(x: .value("Zyklustag", p.day), y: .value("RPE", p.value))
                            .foregroundStyle(Theme.training)
                            .symbolSize(Double(20 + p.count * 10))
                    }
                    .chartYScale(domain: 1...10)
                    .chartXAxisLabel("Zyklustag")
                    .frame(height: 140)
                    .accessibilityLabel("Trainingsbelastung nach Zyklustag")
                } else {
                    Text("Zu wenige Trainings mit Belastungsangabe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Dargestellt sind zeitliche Zusammenhänge in deinen eigenen Daten. Sie belegen keine Ursachen und ersetzen keine medizinische Beurteilung.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dashboard-Karte

struct CycleTodayCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \CycleDay.date) private var days: [CycleDay]

    var body: some View {
        Card {
            CardHeader(title: "Zyklus", symbol: "circle.dashed", tint: Theme.cycle) {
                NavigationLink(value: AppDestination.cycle) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Zyklus öffnen")
            }
            if prefs.lockSensitiveModules {
                NavigationLink(value: AppDestination.cycle) {
                    Label("Geschützt – tippe zum Öffnen", systemImage: "lock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                let stats = CycleCalculator.stats(days, defaultLength: prefs.cycleLengthDays)
                let today = days.first { $0.dayKey == DayKey.today }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline(stats, today: today))
                            .font(.headline)
                        Text(detail(stats))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(CycleFlow.allCases) { flow in
                            Button {
                                CycleCalculator.setFlow(flow, on: .now, in: context)
                            } label: {
                                if today?.flow == flow {
                                    Label(flow.title, systemImage: "checkmark")
                                } else {
                                    Text(flow.title)
                                }
                            }
                        }
                    } label: {
                        Label("Erfassen", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private func headline(_ stats: CycleStats, today: CycleDay?) -> String {
        if today?.flow.isBleeding == true { return "Periode · Tag \(stats.currentCycleDay ?? 1)" }
        if let day = stats.currentCycleDay { return "Zyklustag \(day)" }
        return "Noch kein Beginn erfasst"
    }

    private func detail(_ stats: CycleStats) -> String {
        guard let until = stats.daysUntilNextPeriod() else { return "Erfasse deine Periode, um Schätzungen zu sehen." }
        if until > 0 { return "Nächste Periode in etwa \(until) Tag\(until == 1 ? "" : "en") (Schätzung)" }
        if until == 0 { return "Periode heute erwartet (Schätzung)" }
        return "Erwarteter Beginn vor \(-until) Tag\(until == -1 ? "" : "en") (Schätzung)"
    }
}
