import Foundation
import SwiftData

/// Strukturierte Aktion, die der Coach aus einer Nutzereingabe ableitet.
/// Aktionen werden vor dem Anwenden validiert und – ausser bei freigegebenen
/// Automatisierungen – erst nach Bestätigung ausgeführt.
struct CoachAction: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case logWeight, logWater, logFood, addWorkoutNote, setSessionExertion, logSupplement,
             navigate, openSettings, changeGoal, setWaterTarget, deleteLastWeight, deleteEntry,
             startWorkout, searchEntries
    }

    enum Status: String, Codable {
        case proposed, applied, rejected, undone, needsInput, failed
    }

    var id: UUID = UUID()
    var kind: Kind
    var status: Status = .proposed
    var title: String
    var detail: String = ""
    var params: [String: String] = [:]
    /// Wählbare Optionen, wenn eine Angabe fehlt (z. B. Menge, Trainingseinheit).
    var choices: [CoachChoice] = []
    var isDestructive: Bool = false
    /// Wert wurde aus der Formulierung abgeleitet (z. B. Belastung) und sollte geprüft werden.
    var isDerived: Bool = false
    /// Wurde über eine freigegebene Automatisierungsregel ohne Vorschau angewendet.
    var wasAutoApplied: Bool = false
    var auditEntryID: UUID? = nil
    var resultNote: String? = nil

    init(kind: Kind, title: String, detail: String = "", params: [String: String] = [:],
         status: Status = .proposed, choices: [CoachChoice] = [], isDestructive: Bool = false, isDerived: Bool = false) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.params = params
        self.status = status
        self.choices = choices
        self.isDestructive = isDestructive
        self.isDerived = isDerived
    }

    var symbol: String {
        switch kind {
        case .logWeight, .deleteLastWeight: "scalemass"
        case .logWater, .setWaterTarget: "drop"
        case .logFood: "fork.knife"
        case .addWorkoutNote: "note.text"
        case .setSessionExertion: "gauge.with.dots.needle.67percent"
        case .logSupplement: "pills"
        case .navigate, .openSettings: "arrow.up.forward.app"
        case .changeGoal: "target"
        case .deleteEntry: "trash"
        case .startWorkout: "dumbbell"
        case .searchEntries: "magnifyingglass"
        }
    }

    /// Navigationsaktionen werden ohne Protokolleintrag direkt ausgeführt.
    var isNavigation: Bool { kind == .navigate || kind == .openSettings || kind == .startWorkout }

    /// Kann nach dem Anwenden rückgängig gemacht werden.
    var isUndoable: Bool {
        switch kind {
        case .logWeight, .logWater, .logFood, .logSupplement, .addWorkoutNote, .setSessionExertion,
             .changeGoal, .setWaterTarget, .deleteLastWeight: true
        default: false
        }
    }

    /// Schlüssel für Automatisierungsregeln in `AppPreferences.coachAutomations`.
    var automationKey: String? {
        switch kind {
        case .logWater: "water.autoApply"
        case .logWeight: "weight.autoApply"
        case .logSupplement: "supplement.autoApply"
        default: nil
        }
    }
}

struct CoachChoice: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String
    /// Parameter, die bei Auswahl gesetzt werden.
    var params: [String: String]
    /// Auswahl verwirft die Aktion (z. B. „Nicht speichern“).
    var rejects: Bool = false

    init(label: String, params: [String: String], rejects: Bool = false) {
        self.label = label
        self.params = params
        self.rejects = rejects
    }
}

/// Parameter-Schlüssel und Helfer.
enum CoachParam {
    static let kg = "kg"
    static let day = "day"          // yyyy-MM-dd
    static let time = "time"        // HH:mm, nur wenn angegeben
    static let ml = "ml"
    static let beverage = "beverage"
    static let foodID = "foodID"
    static let name = "name"
    static let grams = "grams"
    static let meal = "meal"
    static let kcal100 = "kcal100"
    static let protein100 = "protein100"
    static let carbs100 = "carbs100"
    static let fat100 = "fat100"
    static let note = "note"
    static let sessionID = "sessionID"
    static let exertion = "exertion"
    static let supplementID = "supplementID"
    static let destination = "destination"
    static let section = "section"
    static let goal = "goal"
    static let entityID = "entityID"
    static let previous = "previous"
    static let previousGoals = "previousGoals"
    static let needs = "needs"
    static let quality = "quality"

    static func double(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    static func string(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    /// Datum aus Tagesschlüssel und optionaler Uhrzeit. Ohne Uhrzeit: heute = jetzt
    /// (Erfassungszeitpunkt), frühere Tage = 12:00 als neutraler Platzhalter.
    static func date(day: String?, time: String?, now: Date = .now) -> Date {
        let base = day.flatMap { DayKey.date(from: $0) } ?? now.startOfDay
        let cal = Calendar.current
        if let time {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base) ?? base
            }
        }
        if cal.isDate(base, inSameDayAs: now) { return now }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: base) ?? base
    }

    static func dayDescription(_ day: String?, time: String?) -> String {
        let date = day.flatMap { DayKey.date(from: $0) } ?? .now
        let dayText = Fmt.day(date)
        if let time { return "\(dayText), \(time) Uhr" }
        return "\(dayText) · ohne Uhrzeit"
    }
}

/// Lesen/Schreiben der Aktionen einer Nachricht.
@MainActor
enum CoachActionStore {
    static func actions(of message: CoachMessage) -> [CoachAction] {
        ModelCoding.decode([CoachAction].self, from: message.actionsData, default: [])
    }

    static func setActions(_ actions: [CoachAction], on message: CoachMessage) {
        message.actionsData = ModelCoding.encode(actions)
    }

    static func update(_ message: CoachMessage, actionID: UUID, in context: ModelContext, _ change: (inout CoachAction) -> Void) {
        var all = actions(of: message)
        guard let index = all.firstIndex(where: { $0.id == actionID }) else { return }
        change(&all[index])
        setActions(all, on: message)
        context.saveQuietly()
    }
}
