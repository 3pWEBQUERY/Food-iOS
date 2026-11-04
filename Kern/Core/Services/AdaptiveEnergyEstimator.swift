import Foundation

/// Ergebnis der adaptiven Bedarfsschätzung.
struct AdaptiveEstimate: Hashable {
    var tdee: Double
    var observedTDEE: Double
    var formulaTDEE: Double
    var confidence: Double
    var loggedDays: Int
    var windowDays: Int
    var weightCount: Int
    var averageIntake: Double
    var weightSlopeKgPerWeek: Double
    var isReliable: Bool

    var explanation: String {
        """
        In den letzten \(windowDays) Tagen hast du an \(loggedDays) Tagen vollständig erfasst \
        (Ø \(Fmt.number(averageIntake)) kcal). Dein Gewichtstrend liegt bei \(Fmt.signed(weightSlopeKgPerWeek, digits: 2)) kg pro Woche. \
        Daraus ergibt sich ein beobachteter Bedarf von etwa \(Fmt.number(observedTDEE)) kcal. \
        Gewichtet mit der Formel (\(Fmt.number(formulaTDEE)) kcal) und einer Datensicherheit von \(Fmt.percent(confidence)) \
        schätzt Kern deinen Bedarf auf \(Fmt.number(tdee)) kcal.
        """
    }
}

/// Verbessert die Formel-Schätzung schrittweise anhand von Gewichtsverlauf und Kalorienaufnahme.
/// Einzelne Messungen lösen keine Änderung aus: Es werden mindestens 14 erfasste Tage
/// und 6 Wägungen über mindestens 14 Tage benötigt.
enum AdaptiveEnergyEstimator {
    static let minimumLoggedDays = 14
    static let minimumWeighIns = 6
    static let minimumDayKcal = 800.0
    static let maxChangePerUpdate = 150.0

    /// - Parameters:
    ///   - intakeByDay: Kalorien pro Tagesschlüssel.
    ///   - weights: Gewichtsmessungen (Datum, kg).
    ///   - formulaTDEE: Gesamtbedarf laut Formel.
    ///   - previous: zuletzt akzeptierte adaptive Schätzung.
    static func estimate(intakeByDay: [String: Double], weights: [(date: Date, kg: Double)], formulaTDEE: Double,
                         previous: Double?, now: Date = .now, windowDays: Int = 28) -> AdaptiveEstimate? {
        let keys = DayKey.range(endingAt: now.adding(days: -1), count: windowDays)
        let complete = keys.compactMap { intakeByDay[$0] }.filter { $0 >= minimumDayKcal }
        guard complete.count >= minimumLoggedDays else { return nil }

        let windowStart = now.adding(days: -windowDays).startOfDay
        let inWindow = weights.filter { $0.date >= windowStart && $0.date <= now }.sorted { $0.date < $1.date }
        guard inWindow.count >= minimumWeighIns,
              let first = inWindow.first, let last = inWindow.last,
              last.date.timeIntervalSince(first.date) >= 14 * 86_400 else { return nil }

        // Lineare Regression (kg pro Tag) – robust gegenüber einzelnen Ausreissern durch Trend über viele Punkte.
        let xs = inWindow.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = inWindow.map(\.kg)
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0 else { return nil }
        let slopePerDay = num / den

        let avgIntake = complete.reduce(0, +) / Double(complete.count)
        var observed = avgIntake - slopePerDay * EnergyCalculator.kcalPerKgBodyMass
        // Plausibilitätsgrenzen relativ zur Formel
        observed = observed.clamped((formulaTDEE * 0.65)...(formulaTDEE * 1.35))

        let completeness = Double(complete.count) / Double(windowDays)
        let weighInDensity = min(1, Double(inWindow.count) / 12)
        let confidence = (completeness * weighInDensity).clamped(0...0.85)

        var blended = formulaTDEE * (1 - confidence) + observed * confidence
        let reference = previous ?? formulaTDEE
        blended = blended.clamped((reference - maxChangePerUpdate)...(reference + maxChangePerUpdate))

        return AdaptiveEstimate(
            tdee: blended.rounded(toNearest: 10),
            observedTDEE: observed.rounded(toNearest: 10),
            formulaTDEE: formulaTDEE.rounded(toNearest: 10),
            confidence: confidence,
            loggedDays: complete.count,
            windowDays: windowDays,
            weightCount: inWindow.count,
            averageIntake: avgIntake,
            weightSlopeKgPerWeek: slopePerDay * 7,
            isReliable: confidence >= 0.4
        )
    }

    /// Geglätteter Gewichtstrend (exponentiell gewichteter Mittelwert, α = 0.25).
    static func smoothedTrend(_ weights: [(date: Date, kg: Double)], alpha: Double = 0.25) -> [(date: Date, kg: Double)] {
        let sorted = weights.sorted { $0.date < $1.date }
        var result: [(date: Date, kg: Double)] = []
        var current: Double?
        for w in sorted {
            let next = current.map { $0 + alpha * (w.kg - $0) } ?? w.kg
            current = next
            result.append((w.date, next))
        }
        return result
    }

    /// Trend in kg pro Woche über die letzten `days` Tage (nil bei zu wenigen Daten).
    static func weeklyTrend(_ weights: [(date: Date, kg: Double)], days: Int = 21, now: Date = .now) -> Double? {
        let start = now.adding(days: -days)
        let recent = weights.filter { $0.date >= start }.sorted { $0.date < $1.date }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 6 * 86_400 else { return nil }
        let smooth = smoothedTrend(recent)
        guard let s0 = smooth.first, let s1 = smooth.last else { return nil }
        let daysSpan = s1.date.timeIntervalSince(s0.date) / 86_400
        guard daysSpan > 0 else { return nil }
        return (s1.kg - s0.kg) / daysSpan * 7
    }
}
