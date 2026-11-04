import SwiftUI
import SwiftData
import UIKit

// MARK: - Abfragen

/// Gemeinsame Abfragen des Trainingsmoduls.
@MainActor
enum TrainingQueries {
    static func exerciseMap(in context: ModelContext) -> [String: Exercise] {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func exercise(id: String, in context: ModelContext) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func equipment(id: String, in context: ModelContext) -> Equipment? {
        var descriptor = FetchDescriptor<Equipment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Abgeschlossene Logs einer Übung, neueste zuerst.
    static func completedLogs(exerciseID: String, in context: ModelContext) -> [ExerciseLog] {
        let logs = (try? context.fetch(FetchDescriptor<ExerciseLog>(predicate: #Predicate { $0.exerciseID == exerciseID }))) ?? []
        return logs
            .filter { $0.session?.isCompleted == true }
            .sorted { ($0.session?.startedAt ?? .distantPast) > ($1.session?.startedAt ?? .distantPast) }
    }

    /// Letztes abgeschlossenes Log derselben Übung mit demselben Gerät.
    static func lastLog(exerciseID: String, equipmentID: String?, excluding sessionID: UUID?, in context: ModelContext) -> ExerciseLog? {
        completedLogs(exerciseID: exerciseID, in: context).first { log in
            log.session?.id != sessionID && log.equipmentID == equipmentID && !log.sets.isEmpty
        }
    }

    static func activeGym(in context: ModelContext) -> GymProfile? {
        let gyms = (try? context.fetch(FetchDescriptor<GymProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let id = AppPreferences.shared.activeGymID.flatMap(UUID.init(uuidString:)),
           let gym = gyms.first(where: { $0.id == id }) {
            return gym
        }
        return gyms.first { $0.isDefault } ?? gyms.first
    }

    /// Nächste Vorlage eines Plans: zuerst nie durchgeführte, sonst die am längsten zurückliegende.
    static func nextTemplate(in plan: WorkoutPlan) -> WorkoutTemplate? {
        let templates = plan.sortedTemplates
        if let fresh = templates.first(where: { $0.lastPerformedAt == nil }) { return fresh }
        return templates.min { ($0.lastPerformedAt ?? .distantPast) < ($1.lastPerformedAt ?? .distantPast) }
    }

    /// Kalender mit Wochenbeginn Montag.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        cal.locale = Fmt.locale
        cal.timeZone = .current
        return cal
    }

    static func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date.startOfDay
    }

    /// Kandidaten für einen Übungstausch: hinterlegte Alternativen plus gleiche Hauptmuskelgruppe,
    /// gefiltert nach der verfügbaren Ausstattung des aktiven Studios.
    static func swapCandidates(for exerciseID: String, all: [Exercise], gym: GymProfile?) -> [Exercise] {
        guard let current = all.first(where: { $0.id == exerciseID }) else { return [] }
        let kinds = Set(gym?.availableKinds ?? EquipmentKind.allCases)
        let available: (Exercise) -> Bool = { $0.isBodyweight || kinds.contains($0.equipmentKind) }
        let alternatives = current.alternativeIDs.compactMap { id in all.first { $0.id == id } }.filter(available)
        let sameMuscle = all.filter {
            $0.id != current.id && $0.primaryMuscle == current.primaryMuscle && available($0)
                && !current.alternativeIDs.contains($0.id)
        }.sorted { $0.name < $1.name }
        return alternatives + sameMuscle
    }
}

// MARK: - Mathematik

enum TrainingMath {
    static func roundWeight(_ kg: Double, step: Double = 2.5) -> Double {
        guard step > 0 else { return kg }
        return (kg / step).rounded() * step
    }

    /// Sinnvolle Steigerung je nach Gerät. Ein hinterlegter Geräteschritt hat Vorrang.
    static func increment(for kind: EquipmentKind, equipment: Equipment?) -> Double {
        if let step = equipment?.weightIncrementKg, step > 0 { return step }
        switch kind {
        case .barbell, .smith: return 2.5
        case .machine, .cable: return 2.5
        case .dumbbell: return 2
        case .kettlebell: return 4
        default: return 2.5
        }
    }

    static func setLabel(_ set: SetLog, unit: WeightUnit) -> String {
        if set.weightKg > 0 {
            return "\(Fmt.weight(set.weightKg, unit: unit, digits: 2)) \(unit.symbol) × \(set.reps)"
        }
        if let duration = set.durationSec, duration > 0 { return Fmt.duration(TimeInterval(duration)) }
        return "\(set.reps) Wdh."
    }

    static func repRange(min: Int?, max: Int?) -> String {
        switch (min, max) {
        case let (lo?, hi?) where lo != hi: return "\(lo)–\(hi)"
        case let (lo?, _): return "\(lo)"
        case let (_, hi?): return "\(hi)"
        default: return "–"
        }
    }
}

// MARK: - Gespeicherte Vorgaben (Progression & Deload)

/// Startgewichte, die aus angenommenen Progressionsvorschlägen stammen.
/// Werden beim nächsten Start der Vorlage übernommen und danach entfernt.
enum TrainingTargetWeights {
    private static let key = "kern.training.targetWeights"

    private static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func get(templateID: UUID, exerciseID: String) -> Double? {
        load()["\(templateID.uuidString)|\(exerciseID)"]
    }

    static func set(_ value: Double?, templateID: UUID, exerciseID: String) {
        var all = load()
        all["\(templateID.uuidString)|\(exerciseID)"] = value
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// Geplante leichtere Trainingswoche (−40 % Volumen, ca. −10 % Gewicht).
enum TrainingDeload {
    private static let key = "kern.training.deloadUntil"

    private static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func activeUntil(planID: UUID) -> Date? {
        guard let ts = load()[planID.uuidString] else { return nil }
        let date = Date(timeIntervalSince1970: ts)
        return date > .now ? date : nil
    }

    static func isActive(planID: UUID) -> Bool { activeUntil(planID: planID) != nil }

    static func start(planID: UUID, days: Int = 7) {
        var all = load()
        all[planID.uuidString] = Date.now.adding(days: days).timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: key)
    }

    static func end(planID: UUID) {
        var all = load()
        all[planID.uuidString] = nil
        UserDefaults.standard.set(all, forKey: key)
    }
}

// MARK: - Eingabefeld

/// Zahleneingabe, die beim Tippen sofort übernommen wird (wichtig, wenn direkt danach
/// der Satz abgehakt wird). Akzeptiert Komma und Punkt.
struct TrainingNumberInput: View {
    let value: Double
    var placeholder: String = "–"
    var fractionDigits: Int = 0
    var width: CGFloat = 64
    let onChange: (Double) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .focused($isFocused)
            .frame(width: width)
            .padding(.vertical, 7)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .onAppear { text = format(value) }
            .onChange(of: text) { _, newText in
                if newText.isEmpty {
                    if value != 0 { onChange(0) }
                } else if let parsed = parse(newText), parsed != value {
                    onChange(parsed)
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused, parse(text) != newValue { text = format(newValue) }
            }
    }

    private func format(_ v: Double) -> String {
        v == 0 ? "" : Fmt.decimal(v, maxDigits: fractionDigits).replacingOccurrences(of: "’", with: "")
    }

    private func parse(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}

@MainActor
func trainingHideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Wochenleiste

/// Sieben Tage (Mo–So) der aktuellen Woche mit Markierung absolvierter Trainings.
struct TrainingWeekStrip: View {
    let sessions: [WorkoutSession]
    var referenceDate: Date = .now

    var body: some View {
        let cal = TrainingQueries.calendar
        let start = TrainingQueries.weekStart(for: referenceDate)
        let trainedDays = Set(sessions.filter(\.isCompleted).map { DayKey.make($0.startedAt) })
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
                let trained = trainedDays.contains(DayKey.make(day))
                let isToday = cal.isDateInToday(day)
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow).locale(Fmt.locale)))
                        .font(.caption2Strong)
                        .foregroundStyle(isToday ? Theme.training : .secondary)
                    ZStack {
                        Circle()
                            .fill(trained ? Theme.training : Theme.fill)
                        if trained {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        } else {
                            Text(day.formatted(.dateTime.day().locale(Fmt.locale)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(isToday ? .primary : .secondary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .overlay {
                        if isToday && !trained {
                            Circle().strokeBorder(Theme.training, lineWidth: 1.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).locale(Fmt.locale)))
                .accessibilityValue(trained ? "Trainiert" : "Kein Training")
            }
        }
    }
}

// MARK: - Textexport

enum TrainingExport {
    static func text(for session: WorkoutSession, unit: WeightUnit) -> String {
        var lines: [String] = []
        lines.append("\(session.name) – \(Fmt.mediumDate(session.startedAt))")
        var meta = ["Dauer \(Fmt.minutes(session.duration))", "\(session.completedSetCount) Sätze"]
        if session.volumeKg > 0 { meta.append("Volumen \(Fmt.weightWithUnit(session.volumeKg, unit: unit, digits: 0))") }
        if let rpe = session.perceivedExertion { meta.append("Belastung \(rpe)/10") }
        lines.append(meta.joined(separator: " · "))
        for log in session.sortedExercises {
            lines.append("")
            lines.append(log.exerciseName + (log.equipmentLabel.map { " (\($0))" } ?? ""))
            var workingIndex = 0
            for set in log.sortedSets {
                let prefix: String
                if set.kind == .working {
                    workingIndex += 1
                    prefix = "\(workingIndex)."
                } else {
                    prefix = set.kind.shortLabel
                }
                var line = "  \(prefix) \(TrainingMath.setLabel(set, unit: unit))"
                if let rir = set.rir { line += " · RIR \(rir)" }
                if let rpe = set.rpe { line += " · RPE \(Fmt.decimal(rpe))" }
                lines.append(line)
            }
            if !log.notes.isEmpty { lines.append("  Notiz: \(log.notes)") }
        }
        if !session.notes.isEmpty {
            lines.append("")
            lines.append("Notizen: \(session.notes)")
        }
        return lines.joined(separator: "\n")
    }

    static func text(for plan: WorkoutPlan, exercises: [String: Exercise]) -> String {
        var lines = ["\(plan.name) · \(plan.daysPerWeek) Tage pro Woche"]
        if !plan.notes.isEmpty { lines.append(plan.notes) }
        for template in plan.sortedTemplates {
            lines.append("")
            lines.append(template.name)
            for item in template.exercises {
                let name = exercises[item.exerciseID]?.name ?? item.exerciseID
                var line = "  • \(name): \(item.sets) × \(TrainingMath.repRange(min: item.repMin, max: item.repMax))"
                if let rir = item.targetRIR { line += ", RIR \(rir)" }
                line += ", Pause \(item.restSeconds) s"
                if let group = item.supersetGroup { line += " (Supersatz \(group))" }
                lines.append(line)
            }
        }
        lines.append("")
        lines.append("Erstellt mit Kern")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Kleine Bausteine

/// Kreis mit Satznummer oder Satzart (W, D, F).
struct TrainingSetBadge: View {
    let set: SetLog
    let workingIndex: Int

    var body: some View {
        let label = set.kind == .working ? "\(workingIndex)" : set.kind.shortLabel
        let tint: Color = switch set.kind {
        case .warmup: .secondary
        case .working: .primary
        case .drop: Theme.training
        case .failure: Theme.warning
        }
        Text(label)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(set.isCompleted ? Color.white : tint)
            .frame(width: 28, height: 28)
            .background(set.isCompleted ? Theme.training : Theme.fill, in: Circle())
            .accessibilityLabel(set.kind == .working ? "Satz \(workingIndex)" : set.kind.title)
    }
}

/// Auswahl für RIR/RPE eines Satzes.
struct TrainingEffortMenu: View {
    @Bindable var set: SetLog

    var body: some View {
        Menu {
            Section("Wiederholungen im Tank (RIR)") {
                ForEach(0...5, id: \.self) { value in
                    Button("RIR \(value)") { set.rir = value; set.rpe = nil }
                }
            }
            Section("Anstrengung (RPE)") {
                ForEach([6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                    Button("RPE \(Fmt.decimal(value))") { set.rpe = value; set.rir = nil }
                }
            }
            if set.rir != nil || set.rpe != nil {
                Button("Entfernen", role: .destructive) { set.rir = nil; set.rpe = nil }
            }
        } label: {
            Text(label)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(set.rir == nil && set.rpe == nil ? .tertiary : .secondary)
                .frame(minWidth: 44, minHeight: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Anstrengung")
        .accessibilityValue(label)
    }

    private var label: String {
        if let rir = set.rir { return "RIR \(rir)" }
        if let rpe = set.rpe { return "RPE \(Fmt.decimal(rpe))" }
        return "RIR"
    }
}
