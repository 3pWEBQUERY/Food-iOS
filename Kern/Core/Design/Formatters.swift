import Foundation

/// Einheitliche Formatierung (Schweizer Schreibweise, z. B. 1’250).
enum Fmt {
    static let locale = Locale(identifier: "de_CH")

    static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// Zahl mit bis zu `maxDigits` Nachkommastellen, ohne überflüssige Nullen.
    static func decimal(_ value: Double, maxDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxDigits)).locale(locale))
    }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        let text = decimal(abs(value), maxDigits: digits)
        if abs(value) < 0.0001 { return "±0" }
        return value > 0 ? "+\(text)" : "−\(text)"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    // MARK: Energie

    static func energy(_ kcal: Double, unit: EnergyUnit) -> String {
        switch unit {
        case .kcal: number(kcal)
        case .kJ: number(kcal * 4.184)
        }
    }

    static func energyWithUnit(_ kcal: Double, unit: EnergyUnit) -> String {
        "\(energy(kcal, unit: unit)) \(unit.symbol)"
    }

    // MARK: Gewicht

    static func weight(_ kg: Double, unit: WeightUnit, digits: Int = 1) -> String {
        decimal(unit.fromKg(kg), maxDigits: digits)
    }

    static func weightWithUnit(_ kg: Double, unit: WeightUnit, digits: Int = 1) -> String {
        "\(weight(kg, unit: unit, digits: digits)) \(unit.symbol)"
    }

    // MARK: Volumen

    static func volume(_ ml: Double) -> String {
        if ml >= 1000 {
            return "\(decimal(ml / 1000, maxDigits: 2)) l"
        }
        return "\(number(ml)) ml"
    }

    // MARK: Datum & Zeit

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60) h \(m % 60) min" }
        return "\(m) min"
    }

    static func minuteOfDay(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

/// Stabile Tagesschlüssel (yyyy-MM-dd) für schnelle Abfragen pro Tag.
enum DayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static var today: String { make(.now) }

    /// Schlüssel der letzten `count` Tage inklusive `end`, älteste zuerst.
    static func range(endingAt end: Date = .now, count: Int, calendar: Calendar = .current) -> [String] {
        (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map { make($0, calendar: calendar) }
        }
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Kombiniert das Datum mit der aktuellen Uhrzeit (für Einträge an vergangenen Tagen).
    func withCurrentTime(_ now: Date = .now) -> Date {
        let cal = Calendar.current
        if cal.isDate(self, inSameDayAs: now) { return now }
        let time = cal.dateComponents([.hour, .minute], from: now)
        return cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: self) ?? self
    }
}

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
    func rounded(toNearest step: Double) -> Double { (self / step).rounded() * step }
}

extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
