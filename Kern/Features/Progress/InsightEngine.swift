import SwiftUI
import SwiftData

/// Art einer Aussage. Kern unterscheidet konsequent zwischen beobachteten Daten,
/// Schätzungen und Vorschlägen – Ursachen werden nie behauptet.
enum InsightKind: String, CaseIterable {
    case observation, estimate, suggestion, caution

    var title: String {
        switch self {
        case .observation: "Beobachtung"
        case .estimate: "Schätzung"
        case .suggestion: "Vorschlag"
        case .caution: "Hinweis"
        }
    }

    var tint: Color {
        switch self {
        case .observation: Theme.protein
        case .estimate: Theme.weight
        case .suggestion: Theme.accent
        case .caution: Theme.warning
        }
    }
}

struct Insight: Identifiable, Hashable {
    var id = UUID()
    var kind: InsightKind
    var title: String
    var detail: String
    var symbol: String
}

struct WeeklyReport {
    var periodTitle: String
    var headline: String
    var items: [Insight]
}

/// Zusammenfassung über vier Wochen für die gemeinsame Fortschrittslogik.
struct ProgressCombinedSummary {
    var averageIntake: Double?
    var loggedDays: Int
    var weightTrendPerWeek: Double?
    var sessions: Int
    var improvedLifts: [String]
    var declinedLifts: [String]
    var statement: String
}

/// Monatswerte für Langzeitvergleiche.
struct ProgressMonthSummary: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var averageWeightKg: Double?
    var averageIntake: Double?
    var loggedDays: Int
    var sessions: Int
}

/// Erstellt nachvollziehbare Auswertungen aus allen Bereichen.
@MainActor
enum InsightEngine {

    // MARK: Wochenanalyse

    static func weeklyReport(in context: ModelContext, profile: UserProfile, now: Date = .now) -> WeeklyReport {
        let end = now.startOfDay.adding(days: 1)
        let start = end.adding(days: -7)
        let previousStart = start.adding(days: -7)
        let goal = profile.primaryGoal

        var items: [Insight] = []

        // Daten laden
        let foods = ProgressData.foodEntries(in: context, from: previousStart, to: end)
        let thisFoods = foods.filter { $0.date >= start }
        let prevFoods = foods.filter { $0.date < start }
        let allWeights = ProgressData.weightPoints(in: context)
        let water = ProgressData.waterEntries(in: context, from: start, to: end)
        let sessionsThis = ProgressData.sessions(in: context, from: start, to: end)
        let sessionsPrev = ProgressData.sessions(in: context, from: previousStart, to: start)
        let sessionsBefore = ProgressData.sessions(in: context, from: start.adding(days: -56), to: start)

        // 1. Gewicht
        let weightResult = weightInsight(allWeights, start: start, end: end, goal: goal)
        items.append(contentsOf: weightResult.items)

        // 2. Ernährung
        let kcalThis = ProgressData.kcalByDay(thisFoods)
        let kcalPrev = ProgressData.kcalByDay(prevFoods)
        let loggedThis = kcalThis.values.filter { $0 >= AdaptiveEnergyEstimator.minimumDayKcal }
        let loggedPrev = kcalPrev.values.filter { $0 >= AdaptiveEnergyEstimator.minimumDayKcal }
        var avgThis: Double?
        if loggedThis.count >= 3 {
            let avg = loggedThis.reduce(0, +) / Double(loggedThis.count)
            avgThis = avg
            let sd = standardDeviation(loggedThis)
            let variability = avg > 0 ? sd / avg : 0
            let consistency = variability < 0.12 ? "sehr gleichmässig" : variability < 0.22 ? "recht gleichmässig" : "schwankend"
            var proteinByDay: [String: Double] = [:]
            for e in thisFoods { proteinByDay[e.dayKey, default: 0] += e.nutrients.protein }
            let proteinHits = proteinByDay.values.filter { $0 >= Double(profile.proteinTargetG) * 0.9 }.count
            items.append(Insight(
                kind: .observation,
                title: "Ernährung an \(loggedThis.count) von 7 Tagen erfasst",
                detail: "Ø \(Fmt.number(avg)) kcal bei einem Ziel von \(Fmt.number(Double(profile.calorieTarget))) kcal. Die Tageswerte waren \(consistency) (± \(Fmt.number(sd)) kcal). Proteinziel an \(proteinHits) Tag(en) erreicht.",
                symbol: "fork.knife"))
        } else if !thisFoods.isEmpty {
            items.append(Insight(kind: .observation, title: "Ernährung lückenhaft erfasst",
                                 detail: "Nur \(loggedThis.count) vollständig erfasste Tag(e). Für eine Aussage zur Konstanz braucht es mindestens drei.",
                                 symbol: "fork.knife"))
        }

        // 3. Training
        let target = max(profile.weeklyWorkoutTarget, 1)
        let volumeThis = sessionsThis.reduce(0) { $0 + $1.volumeKg }
        let volumePrev = sessionsPrev.reduce(0) { $0 + $1.volumeKg }
        if !sessionsThis.isEmpty || profile.weeklyWorkoutTarget > 0 {
            let reached = sessionsThis.count >= target
            var detail = "\(sessionsThis.count) von \(target) geplanten Einheiten absolviert."
            if volumeThis > 0 {
                detail += " Trainingsvolumen: \(Fmt.number(volumeThis)) kg"
                if volumePrev > 0 {
                    detail += " (\(Fmt.signed((volumeThis - volumePrev) / volumePrev * 100, digits: 0)) % zur Vorwoche)."
                } else {
                    detail += "."
                }
            }
            items.append(Insight(kind: .observation,
                                 title: reached ? "Trainingsziel erreicht" : "Trainingsziel noch offen",
                                 detail: detail, symbol: "dumbbell"))
        }

        // 4. Verbesserte Übungen
        let lifts = ProgressData.liftComparison(recent: sessionsThis, before: sessionsBefore)
        if !lifts.improved.isEmpty {
            let names = lifts.improved.prefix(3).joined(separator: ", ")
            items.append(Insight(kind: .observation, title: "\(lifts.improved.count) Übung(en) verbessert",
                                 detail: "Höherer geschätzter 1RM als in den 8 Wochen davor: \(names). Verglichen wird nur am gleichen Gerät.",
                                 symbol: "chart.line.uptrend.xyaxis"))
        } else if !sessionsThis.isEmpty && !sessionsBefore.isEmpty {
            items.append(Insight(kind: .observation, title: "Kraftwerte stabil",
                                 detail: "Diese Woche keine neuen Bestwerte gegenüber den 8 Wochen davor. Das ist in vielen Phasen normal.",
                                 symbol: "chart.line.flattrend.xyaxis"))
        }

        // 5. Wasser
        var waterByDay: [String: Double] = [:]
        for w in water { waterByDay[w.dayKey, default: 0] += w.ml }
        if !waterByDay.isEmpty {
            let avg = waterByDay.values.reduce(0, +) / Double(waterByDay.count)
            let ratio = profile.waterTargetMl > 0 ? avg / Double(profile.waterTargetMl) : 0
            items.append(Insight(kind: .observation, title: "Ø \(Fmt.volume(avg)) Flüssigkeit",
                                 detail: "An \(waterByDay.count) erfassten Tagen, das sind \(Fmt.percent(ratio)) deines Trinkziels.",
                                 symbol: "drop"))
        }

        // 6. Supplements
        if let adherence = supplementAdherence(in: context, from: start, to: end) {
            items.append(Insight(kind: .observation, title: "Supplement-Routine zu \(Fmt.percent(adherence)) eingehalten",
                                 detail: "Bezogen auf deine eingeplanten Einnahmen der letzten 7 Tage.",
                                 symbol: "pills"))
        }

        // 7. Auffällige Veränderungen
        if loggedThis.count >= 3, loggedPrev.count >= 3, let avgThis {
            let avgPrev = loggedPrev.reduce(0, +) / Double(loggedPrev.count)
            let change = (avgThis - avgPrev) / max(avgPrev, 1)
            if abs(change) > 0.15 {
                items.append(Insight(kind: .caution, title: "Deutlich veränderte Kalorienaufnahme",
                                     detail: "Ø \(Fmt.signed(change * 100, digits: 0)) % gegenüber der Vorwoche (\(Fmt.number(avgPrev)) → \(Fmt.number(avgThis)) kcal). Möglicherweise wurde auch unterschiedlich vollständig erfasst.",
                                     symbol: "exclamationmark.triangle"))
            }
        }
        if volumePrev > 0, volumeThis > 0, abs(volumeThis - volumePrev) / volumePrev > 0.3 {
            items.append(Insight(kind: .caution, title: "Trainingsvolumen stark verändert",
                                 detail: "Grössere Sprünge im Volumen können die Regeneration beeinflussen. Achte auf deine Tagesform.",
                                 symbol: "waveform.path.ecg"))
        }

        // 8. Nächste Schritte
        var suggestions: [Insight] = []
        if loggedThis.count < 5 {
            suggestions.append(Insight(kind: .suggestion, title: "Mehr Tage vollständig erfassen",
                                       detail: "Ab etwa 5 erfassten Tagen pro Woche werden Trends und die adaptive Bedarfsschätzung deutlich verlässlicher.",
                                       symbol: "square.and.pencil"))
        }
        if sessionsThis.count < target {
            suggestions.append(Insight(kind: .suggestion, title: "Training einplanen",
                                       detail: "Plane die fehlenden \(target - sessionsThis.count) Einheit(en) fix im Kalender ein – auch kürzere Einheiten zählen.",
                                       symbol: "calendar.badge.plus"))
        }
        if weightResult.weighIns < 3 {
            suggestions.append(Insight(kind: .suggestion, title: "Regelmässiger wiegen",
                                       detail: "3–7 Messungen pro Woche, möglichst morgens unter gleichen Bedingungen, glätten normale Tagesschwankungen.",
                                       symbol: "scalemass"))
        }
        items.append(contentsOf: suggestions.prefix(3))

        if items.isEmpty {
            items.append(Insight(kind: .observation, title: "Zu wenige Daten für eine Aussage",
                                 detail: "Erfasse Mahlzeiten, Gewicht oder Trainings – nach einigen Tagen entsteht hier deine Wochenanalyse.",
                                 symbol: "tray"))
        }

        let headline = makeHeadline(goal: goal, weightDelta: weightResult.delta, improved: lifts.improved.count,
                                    sessions: sessionsThis.count, target: target, loggedDays: loggedThis.count)
        return WeeklyReport(periodTitle: periodTitle(start: start, end: end.adding(days: -1)), headline: headline, items: items)
    }

    private static func weightInsight(_ weights: [(date: Date, kg: Double)], start: Date, end: Date,
                                      goal: FitnessGoal) -> (items: [Insight], delta: Double?, weighIns: Int) {
        let inWeek = weights.filter { $0.date >= start && $0.date < end }
        let smooth = AdaptiveEnergyEstimator.smoothedTrend(weights.filter { $0.date < end })
        guard inWeek.count >= 2,
              let current = smooth.last(where: { $0.date < end }),
              let before = smooth.last(where: { $0.date < start }) else {
            let text = inWeek.isEmpty
                ? "Diese Woche wurde kein Gewicht erfasst."
                : "Für einen Trend braucht es mindestens zwei Messungen in der Woche und eine davor."
            return ([Insight(kind: .observation, title: "Gewichtstrend: zu wenige Daten", detail: text, symbol: "scalemass")], nil, inWeek.count)
        }
        let delta = current.kg - before.kg
        var items = [Insight(
            kind: .observation,
            title: "Gewichtstrend \(Fmt.signed(delta, digits: 1)) kg",
            detail: "Geglätteter Trend aus \(inWeek.count) Messungen diese Woche: \(Fmt.decimal(before.kg)) → \(Fmt.decimal(current.kg)) kg.",
            symbol: "scalemass")]

        let fits: Bool?
        switch goal.energyStrategy {
        case .deficit: fits = delta < -0.05
        case .slightDeficit: fits = delta < 0.15
        case .maintenance: fits = abs(delta) < 0.35
        case .leanSurplus: fits = delta > -0.1 && delta < 0.45
        case .surplus: fits = delta > 0.05
        }
        if let fits {
            items.append(Insight(
                kind: .estimate,
                title: fits ? "Passt bisher zu deinem Ziel" : "Weicht von deinem Ziel ab",
                detail: fits
                    ? "Die Entwicklung entspricht der Richtung, die für „\(goal.title)“ zu erwarten ist. Eine Woche ist allerdings ein kurzer Zeitraum."
                    : "Die Richtung entspricht noch nicht „\(goal.title)“. Kurzfristige Schwankungen durch Wasser, Salz oder Verdauung sind häufig – beobachte den Trend über 2–3 Wochen, bevor du etwas änderst.",
                symbol: "target"))
        }
        return (items, delta, inWeek.count)
    }

    private static func makeHeadline(goal: FitnessGoal, weightDelta: Double?, improved: Int, sessions: Int,
                                     target: Int, loggedDays: Int) -> String {
        if let weightDelta, improved >= 2, weightDelta > 0.05,
           goal == .buildMuscle || goal == .gainWeight || goal == .recomposition {
            return "Dein Gewicht ist leicht gestiegen und mehrere Übungen haben sich verbessert. Das passt bisher zu deinem Ziel."
        }
        if let weightDelta, goal == .loseWeight, weightDelta < -0.05 {
            return improved > 0
                ? "Dein Gewichtstrend sinkt, während deine Kraft erhalten bleibt oder steigt – eine gute Woche."
                : "Dein Gewichtstrend sinkt wie geplant."
        }
        if sessions >= target && loggedDays >= 5 {
            return "Sehr konstante Woche: Training und Ernährung wurden zuverlässig erfasst."
        }
        if loggedDays == 0 && sessions == 0 && weightDelta == nil {
            return "Diese Woche liegen noch kaum Daten vor."
        }
        return "Hier ist deine Woche im Überblick – mit dem, was die Daten zeigen, und dem, was offen bleibt."
    }

    // MARK: Supplements

    /// Anteil eingehaltener, eingeplanter Einnahmen (nil, wenn nichts eingeplant).
    static func supplementAdherence(in context: ModelContext, from start: Date, to end: Date) -> Double? {
        let supplements = ((try? context.fetch(FetchDescriptor<Supplement>())) ?? []).filter { $0.isActive && $0.frequency != .asNeeded }
        guard !supplements.isEmpty else { return nil }
        let intakes = (try? context.fetch(FetchDescriptor<SupplementIntake>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        var expected = 0
        var taken = 0
        var day = start
        while day < end {
            let key = DayKey.make(day)
            for s in supplements where s.isScheduled(on: day) && s.createdAt <= day.adding(days: 1) {
                let planned = max(s.scheduleMinutes.count, 1)
                expected += planned
                let count = intakes.filter { $0.supplementID == s.id && $0.dayKey == key }.count
                taken += min(count, planned)
            }
            day = day.adding(days: 1)
        }
        guard expected > 0 else { return nil }
        return Double(taken) / Double(expected)
    }

    // MARK: Vier-Wochen-Zusammenhang

    static func combinedSummary(in context: ModelContext, profile: UserProfile, now: Date = .now) -> ProgressCombinedSummary {
        let end = now.startOfDay.adding(days: 1)
        let start = end.adding(days: -28)
        let foods = ProgressData.foodEntries(in: context, from: start, to: end)
        let logged = ProgressData.kcalByDay(foods).values.filter { $0 >= AdaptiveEnergyEstimator.minimumDayKcal }
        let avgIntake = logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count)
        let trend = AdaptiveEnergyEstimator.weeklyTrend(ProgressData.weightPoints(in: context), days: 28, now: now)
        let firstHalf = ProgressData.sessions(in: context, from: start, to: start.adding(days: 14))
        let secondHalf = ProgressData.sessions(in: context, from: start.adding(days: 14), to: end)
        let lifts = ProgressData.liftComparison(recent: secondHalf, before: firstHalf)
        let sessions = firstHalf.count + secondHalf.count

        var parts: [String] = []
        if let trend {
            if abs(trend) < 0.1 {
                parts.append("Dein Gewicht ist in den letzten vier Wochen weitgehend stabil geblieben")
            } else {
                parts.append("Dein durchschnittliches Körpergewicht ist in den letzten vier Wochen \(trend > 0 ? "gestiegen" : "gesunken") (\(Fmt.signed(trend, digits: 2)) kg pro Woche)")
            }
        }
        if !lifts.improved.isEmpty {
            parts.append("gleichzeitig haben sich \(lifts.improved.count) Übung(en) verbessert")
        } else if sessions > 0 {
            parts.append("deine Kraftwerte sind etwa gleich geblieben")
        }
        var statement: String
        if parts.isEmpty {
            statement = "Sobald Gewicht, Ernährung und Training über einige Wochen erfasst sind, zeigt Kern hier, wie sie zusammenhängen."
        } else {
            statement = parts.joined(separator: ", ") + "."
            if let trend {
                let fits: Bool
                switch profile.primaryGoal.energyStrategy {
                case .deficit: fits = trend < -0.05
                case .slightDeficit: fits = trend < 0.1
                case .maintenance: fits = abs(trend) < 0.2
                case .leanSurplus: fits = trend > -0.05 && trend < 0.4
                case .surplus: fits = trend > 0.05
                }
                statement += fits
                    ? " Die Entwicklung passt bisher zu deinem Ziel „\(profile.primaryGoal.title)“."
                    : " Die Entwicklung entspricht noch nicht ganz deinem Ziel „\(profile.primaryGoal.title)“."
            }
            if let avgIntake {
                statement += " Ø Aufnahme: \(Fmt.number(avgIntake)) kcal an \(logged.count) erfassten Tagen."
            }
        }
        return ProgressCombinedSummary(averageIntake: avgIntake, loggedDays: logged.count, weightTrendPerWeek: trend,
                                       sessions: sessions, improvedLifts: lifts.improved, declinedLifts: lifts.declined,
                                       statement: statement)
    }

    // MARK: Langzeit

    static func monthlySummaries(in context: ModelContext, months: Int = 12, now: Date = .now) -> [ProgressMonthSummary] {
        let cal = Calendar.current
        guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let rangeStart = cal.date(byAdding: .month, value: -(months - 1), to: thisMonth) else { return [] }
        let foods = ProgressData.foodEntries(in: context, from: rangeStart, to: now.adding(days: 1))
        let weights = ProgressData.weights(in: context).filter { $0.date >= rangeStart }
        let sessions = ProgressData.sessions(in: context, from: rangeStart, to: now.adding(days: 1))
        let kcal = ProgressData.kcalByDay(foods)

        var result: [ProgressMonthSummary] = []
        for offset in 0..<months {
            guard let monthStart = cal.date(byAdding: .month, value: offset, to: rangeStart),
                  let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { continue }
            let monthWeights = weights.filter { $0.date >= monthStart && $0.date < monthEnd }.map(\.kg)
            let monthKcal: [Double] = kcal.compactMap { element in
                guard let d = DayKey.date(from: element.key), d >= monthStart, d < monthEnd,
                      element.value >= AdaptiveEnergyEstimator.minimumDayKcal else { return nil }
                return element.value
            }
            let count = sessions.filter { $0.startedAt >= monthStart && $0.startedAt < monthEnd }.count
            result.append(ProgressMonthSummary(
                key: DayKey.make(monthStart),
                title: monthStart.formatted(.dateTime.month(.wide).year().locale(Fmt.locale)),
                averageWeightKg: monthWeights.isEmpty ? nil : monthWeights.reduce(0, +) / Double(monthWeights.count),
                averageIntake: monthKcal.isEmpty ? nil : monthKcal.reduce(0, +) / Double(monthKcal.count),
                loggedDays: monthKcal.count,
                sessions: count))
        }
        return result.reversed()
    }

    // MARK: Text-Export

    static func reportText(_ report: WeeklyReport) -> String {
        var lines = ["Kern – Wochenanalyse \(report.periodTitle)", "", report.headline, ""]
        for item in report.items {
            lines.append("[\(item.kind.title)] \(item.title)")
            lines.append(item.detail)
            lines.append("")
        }
        lines.append("Hinweis: Beobachtungen beschreiben zeitliche Zusammenhänge, keine belegten Ursachen.")
        return lines.joined(separator: "\n")
    }

    // MARK: Helfer

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    static func periodTitle(start: Date, end: Date) -> String {
        "\(Fmt.shortDate(start)) – \(Fmt.shortDate(end))"
    }
}
