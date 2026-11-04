import Foundation
import SwiftData
import UserNotifications

/// Eingeplante Einnahme an einem Tag.
struct SupplementSlot: Identifiable {
    let supplement: Supplement
    let minute: Int
    let intake: SupplementIntake?
    var id: String { "\(supplement.id.uuidString)-\(minute)" }
    var isTaken: Bool { intake != nil }
}

/// Summe eines Inhaltsstoffs über mehrere Produkte.
struct SupplementIngredientTotal: Identifiable {
    var id: String { key + unit }
    let key: String
    let title: String
    let amount: Double
    let unit: String
    let products: [String]
}

/// Planung, Auswertung und Erinnerungen für Supplements.
/// Bewusst ohne Dosierungsempfehlungen – es wird nur dokumentiert, was der Nutzer festlegt.
@MainActor
enum SupplementPlanner {

    // MARK: Tagesplan

    static func slots(on date: Date, supplements: [Supplement], intakes: [SupplementIntake]) -> [SupplementSlot] {
        let key = DayKey.make(date)
        var result: [SupplementSlot] = []
        for supplement in supplements where supplement.isScheduled(on: date) {
            let minutes = (supplement.scheduleMinutes.isEmpty ? [480] : supplement.scheduleMinutes).sorted()
            var todays = intakes.filter { $0.supplementID == supplement.id && $0.dayKey == key }
            var assigned: [Int: SupplementIntake] = [:]
            for minute in minutes {
                if let index = todays.firstIndex(where: { $0.scheduledMinute == minute }) {
                    assigned[minute] = todays.remove(at: index)
                }
            }
            // Einnahmen ohne Zeitbezug (z. B. über den Coach) füllen die frühesten offenen Zeitpunkte.
            for minute in minutes where assigned[minute] == nil {
                if let index = todays.firstIndex(where: { $0.scheduledMinute == nil || !minutes.contains($0.scheduledMinute ?? -1) }) {
                    assigned[minute] = todays.remove(at: index)
                }
            }
            for minute in minutes {
                result.append(SupplementSlot(supplement: supplement, minute: minute, intake: assigned[minute]))
            }
        }
        return result.sorted { ($0.minute, $0.supplement.name) < ($1.minute, $1.supplement.name) }
    }

    /// Nimmt eine Einnahme zurück (inkl. Vorratskorrektur über das Protokoll).
    static func undo(_ intake: SupplementIntake, in context: ModelContext) {
        let target: String? = intake.id.uuidString
        let logs = (try? context.fetch(FetchDescriptor<AuditLogEntry>(predicate: #Predicate { $0.entityID == target }))) ?? []
        if let log = logs.first(where: { $0.isUndoable && !$0.isUndone }) {
            LogService.undo(log, in: context)
        } else {
            let supplementID = intake.supplementID
            if let supplement = try? context.fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.id == supplementID })).first,
               let stock = supplement.stockServings {
                supplement.stockServings = stock + intake.servings
            }
            context.delete(intake)
            context.saveQuietly()
        }
    }

    /// Anteil eingehaltener Einnahmen eines Supplements über `days` Tage.
    static func adherence(of supplement: Supplement, intakes: [SupplementIntake], days: Int, now: Date = .now) -> Double? {
        guard supplement.frequency != .asNeeded else { return nil }
        var expected = 0
        var taken = 0
        for offset in 0..<days {
            let day = now.adding(days: -offset)
            guard day.startOfDay >= supplement.createdAt.startOfDay, supplement.isScheduled(on: day) else { continue }
            let planned = max(supplement.scheduleMinutes.count, 1)
            let key = DayKey.make(day)
            expected += planned
            taken += min(intakes.filter { $0.supplementID == supplement.id && $0.dayKey == key }.count, planned)
        }
        guard expected > 0 else { return nil }
        return Double(taken) / Double(expected)
    }

    // MARK: Erinnerungen

    static func updateReminders(for supplement: Supplement) {
        let prefix = "supp.\(supplement.id.uuidString)"
        let enabled = supplement.remindersEnabled && supplement.isActive && supplement.frequency != .asNeeded
        let minutes = supplement.scheduleMinutes
        let weekdays = supplement.frequency == .specificDays ? supplement.weekdays : nil
        let name = supplement.name
        let label = supplement.servingLabel
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            guard enabled else { return }
            guard await NotificationManager.requestAuthorization() else { return }
            for minute in minutes {
                NotificationManager.schedule(id: "\(prefix).\(minute)", title: name,
                                             body: "Zeit für deine geplante Einnahme (\(label)).",
                                             hour: minute / 60, minute: minute % 60, weekdays: weekdays)
            }
        }
    }

    static func removeReminders(for supplement: Supplement) {
        let prefix = "supp.\(supplement.id.uuidString)"
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    // MARK: Inhaltsstoffe

    /// Normalisiert Namen und Einheiten bekannter Nährstoffe (z. B. „Vitamin D3“ → Vitamin D in µg).
    static func normalize(_ ingredient: SupplementIngredient) -> (key: String, title: String, amount: Double, unit: String) {
        let folded = ingredient.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale)
            .trimmingCharacters(in: .whitespaces)
        let unit = ingredient.unit.lowercased().replacingOccurrences(of: "μ", with: "µ")
        func toMg() -> Double {
            switch unit {
            case "g": ingredient.amount * 1000
            case "µg", "mcg", "ug": ingredient.amount / 1000
            default: ingredient.amount
            }
        }
        func toUg() -> Double {
            switch unit {
            case "mg": ingredient.amount * 1000
            case "g": ingredient.amount * 1_000_000
            case "ie", "iu", "i.e.": ingredient.amount / 40
            default: ingredient.amount
            }
        }
        if folded.contains("vitamin d") || folded.contains("cholecalciferol") {
            return ("vitamin-d", "Vitamin D", toUg(), "µg")
        }
        if folded.contains("b12") || folded.contains("cobalamin") {
            return ("vitamin-b12", "Vitamin B12", unit == "ie" || unit == "iu" ? ingredient.amount : toUg(), "µg")
        }
        if folded.contains("vitamin c") || folded.contains("ascorbin") { return ("vitamin-c", "Vitamin C", toMg(), "mg") }
        if folded.contains("magnesium") { return ("magnesium", "Magnesium", toMg(), "mg") }
        if folded.contains("calcium") || folded.contains("kalzium") { return ("calcium", "Calcium", toMg(), "mg") }
        if folded.contains("eisen") || folded.contains("iron") { return ("iron", "Eisen", toMg(), "mg") }
        if folded.contains("zink") || folded.contains("zinc") { return ("zinc", "Zink", toMg(), "mg") }
        if folded.contains("kalium") || folded.contains("potassium") { return ("potassium", "Kalium", toMg(), "mg") }
        if folded.contains("koffein") || folded.contains("caffeine") || folded.contains("coffein") { return ("caffeine", "Koffein", toMg(), "mg") }
        if folded.contains("kreatin") || folded.contains("creatin") { return ("creatine", "Kreatin", toMg() / 1000, "g") }
        if folded.contains("omega") || folded == "epa" || folded == "dha" { return ("omega3", "Omega-3", toMg(), "mg") }
        return (folded, ingredient.name.trimmingCharacters(in: .whitespaces), ingredient.amount, ingredient.unit)
    }

    /// Dokumentierte Tagesmengen aller an diesem Tag eingeplanten Supplements.
    static func plannedTotals(_ supplements: [Supplement], on date: Date = .now) -> [SupplementIngredientTotal] {
        var map: [String: (title: String, amount: Double, unit: String, products: Set<String>)] = [:]
        for s in supplements where s.isScheduled(on: date) {
            let intakesPerDay = Double(max(s.scheduleMinutes.count, 1)) * s.servingsPerIntake
            for ingredient in s.ingredients {
                let n = normalize(ingredient)
                let mapKey = n.key + "|" + n.unit
                var entry = map[mapKey] ?? (n.title, 0, n.unit, [])
                entry.amount += n.amount * intakesPerDay
                entry.products.insert(s.name)
                map[mapKey] = entry
            }
        }
        return map.map { key, value in
            SupplementIngredientTotal(key: String(key.split(separator: "|").first ?? ""), title: value.title,
                                      amount: value.amount, unit: value.unit, products: value.products.sorted())
        }.sorted { $0.title < $1.title }
    }

    /// Tatsächlich dokumentierte Einnahmemengen eines Tages.
    static func takenTotals(_ supplements: [Supplement], intakes: [SupplementIntake], on date: Date = .now) -> [String: Double] {
        let key = DayKey.make(date)
        var result: [String: Double] = [:]
        for intake in intakes where intake.dayKey == key {
            guard let s = supplements.first(where: { $0.id == intake.supplementID }) else { continue }
            for ingredient in s.ingredients {
                let n = normalize(ingredient)
                result[n.key, default: 0] += n.amount * intake.servings
            }
        }
        return result
    }

    /// Inhaltsstoffe, die in mindestens zwei aktiven Produkten vorkommen.
    static func overlaps(_ supplements: [Supplement]) -> [SupplementIngredientTotal] {
        plannedTotals(supplements.filter(\.isActive)).filter { $0.products.count >= 2 }
    }

    /// Vergleichbarer Nährstoff aus Lebensmitteln (Wert, Einheit) für einen normalisierten Schlüssel.
    static func foodValue(for key: String, in nutrients: Nutrients) -> Double? {
        switch key {
        case "magnesium": nutrients.magnesiumMg
        case "calcium": nutrients.calciumMg
        case "iron": nutrients.ironMg
        case "zinc": nutrients.zincMg
        case "potassium": nutrients.potassiumMg
        case "vitamin-c": nutrients.vitaminCMg
        case "vitamin-d": nutrients.vitaminDUg
        case "vitamin-b12": nutrients.vitaminB12Ug
        case "caffeine": nutrients.caffeineMg
        default: nil
        }
    }

    static let comparableKeys: [(key: String, title: String, unit: String)] = [
        ("magnesium", "Magnesium", "mg"), ("calcium", "Calcium", "mg"), ("iron", "Eisen", "mg"),
        ("zinc", "Zink", "mg"), ("vitamin-c", "Vitamin C", "mg"), ("vitamin-d", "Vitamin D", "µg"),
        ("vitamin-b12", "Vitamin B12", "µg"), ("caffeine", "Koffein", "mg")
    ]

    static func formatAmount(_ value: Double) -> String {
        value >= 100 ? Fmt.number(value) : Fmt.decimal(value, maxDigits: value < 1 ? 2 : 1)
    }
}
