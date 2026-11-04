import Foundation

/// Kompakter Tageszustand für Widgets. Wird von der App in die App Group geschrieben
/// und von der Widget-Extension gelesen. Enthält keine sensiblen Detaildaten.
struct WidgetSnapshot: Codable, Hashable {
    var date: Date
    var kcalConsumed: Double
    var kcalTarget: Double
    var proteinConsumed: Double
    var proteinTarget: Double
    var carbsConsumed: Double
    var carbsTarget: Double
    var fatConsumed: Double
    var fatTarget: Double
    var waterMl: Double
    var waterTargetMl: Double
    var latestWeightKg: Double?
    var weightTrendKgPerWeek: Double?
    /// "kg" oder "lb"
    var weightUnit: String
    /// "kcal" oder "kJ"
    var energyUnit: String
    var nextWorkoutName: String?
    var nextWorkoutDetail: String?

    static let appGroup = "group.ch.kernapp.ios"
    static let storageKey = "kern.widget.snapshot"

    static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot? {
        guard let data = sharedDefaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetSnapshot.sharedDefaults?.set(data, forKey: WidgetSnapshot.storageKey)
    }

    /// Stammt der Schnappschuss von einem früheren Tag, werden Tageswerte auf 0 gesetzt.
    func normalizedForToday(now: Date = .now) -> WidgetSnapshot {
        guard !Calendar.current.isDate(date, inSameDayAs: now) else { return self }
        var copy = self
        copy.date = now
        copy.kcalConsumed = 0
        copy.proteinConsumed = 0
        copy.carbsConsumed = 0
        copy.fatConsumed = 0
        copy.waterMl = 0
        return copy
    }

    var kcalRemaining: Double { kcalTarget - kcalConsumed }

    static let placeholder = WidgetSnapshot(
        date: .now, kcalConsumed: 1240, kcalTarget: 2200,
        proteinConsumed: 86, proteinTarget: 140, carbsConsumed: 130, carbsTarget: 240,
        fatConsumed: 42, fatTarget: 70, waterMl: 1250, waterTargetMl: 2500,
        latestWeightKg: 78.4, weightTrendKgPerWeek: -0.3, weightUnit: "kg", energyUnit: "kcal",
        nextWorkoutName: "Oberkörper A", nextWorkoutDetail: "6 Übungen"
    )

    static let empty = WidgetSnapshot(
        date: .now, kcalConsumed: 0, kcalTarget: 2000,
        proteinConsumed: 0, proteinTarget: 120, carbsConsumed: 0, carbsTarget: 220,
        fatConsumed: 0, fatTarget: 70, waterMl: 0, waterTargetMl: 2500,
        latestWeightKg: nil, weightTrendKgPerWeek: nil, weightUnit: "kg", energyUnit: "kcal",
        nextWorkoutName: nil, nextWorkoutDetail: nil
    )
}

/// Warteschlange für Aktionen aus Widgets/Intents, die die App beim nächsten Start übernimmt.
enum WidgetPendingActions {
    struct WaterAddition: Codable, Hashable {
        var ml: Double
        var date: Date
    }

    private static let waterKey = "kern.widget.pendingWater"

    static func appendWater(ml: Double, date: Date = .now) {
        guard let defaults = WidgetSnapshot.sharedDefaults, ml > 0 else { return }
        var queue = pendingWater()
        queue.append(WaterAddition(ml: ml, date: date))
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: waterKey)
        }
    }

    static func pendingWater() -> [WaterAddition] {
        guard let data = WidgetSnapshot.sharedDefaults?.data(forKey: waterKey) else { return [] }
        return (try? JSONDecoder().decode([WaterAddition].self, from: data)) ?? []
    }

    /// Liefert alle ausstehenden Wassereinträge und leert die Warteschlange.
    static func takeWater() -> [WaterAddition] {
        let queue = pendingWater()
        WidgetSnapshot.sharedDefaults?.removeObject(forKey: waterKey)
        return queue
    }
}

/// Formatierung für Widgets (Schweizer Schreibweise). Die Widget-Extension sieht `Fmt` nicht.
enum WidgetFormat {
    static let locale = Locale(identifier: "de_CH")

    static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    static func energy(_ kcal: Double, unit: String) -> String {
        unit == "kJ" ? number(kcal * 4.184) : number(kcal)
    }

    static func weight(_ kg: Double, unit: String) -> String {
        let value = unit == "lb" ? kg * 2.204_622_62 : kg
        return value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    static func volume(_ ml: Double) -> String {
        if ml >= 1000 {
            return "\((ml / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(locale))) l"
        }
        return "\(number(ml)) ml"
    }
}
