import SwiftUI
import SwiftData
import Charts

// MARK: - Nächstes Training

/// Dashboard-Karte: nächstes geplantes Training mit Startknopf.
struct NextWorkoutCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(WorkoutStore.self) private var workouts
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]
    @Query private var exercises: [Exercise]

    private var activePlan: WorkoutPlan? { plans.first(where: \.isActive) }

    var body: some View {
        Card {
            CardHeader(title: "Nächstes Training", symbol: "dumbbell", tint: Theme.training)
            if workouts.hasActiveSession, let session = workouts.activeSession(in: context) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.title3.weight(.semibold))
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text("Läuft seit \(Fmt.duration(timeline.date.timeIntervalSince(session.startedAt)))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Fortsetzen") { router.isWorkoutPresented = true }
                        .buttonStyle(.glassProminent)
                }
            } else if let plan = activePlan, let template = TrainingQueries.nextTemplate(in: plan) {
                let names = template.exercises.compactMap { item in exercises.first { $0.id == item.exerciseID }?.name }
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.title3.weight(.semibold))
                        Text(names.prefix(3).joined(separator: " · ") + (names.count > 3 ? " +\(names.count - 3)" : ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Theme.Space.xs)
                    Button {
                        workouts.start(template: template, plan: plan, name: template.name, in: context)
                        router.isWorkoutPresented = true
                    } label: {
                        Label("Starten", systemImage: "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                }
                if let last = template.lastPerformedAt {
                    Text("Zuletzt \(Fmt.day(last).lowercasedFirstIfWeekday)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Noch kein Plan")
                    .font(.title3.weight(.semibold))
                Text("Kern erstellt dir einen Plan aus deinen Zielen, deiner Zeit und deiner Ausstattung.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Plan erstellen lassen") { router.open(.planGenerator) }
                    .buttonStyle(.glass)
            }
        }
    }
}

private extension String {
    /// Für Sätze wie „Zuletzt gestern“ bzw. „Zuletzt am Montag, 3. November“.
    var lowercasedFirstIfWeekday: String { self == "Heute" || self == "Gestern" ? self.lowercased() : "am \(self)" }
}

// MARK: - Trainingswoche

/// Dashboard-Karte: Trainings dieser Woche im Vergleich zum Wochenziel.
struct TrainingWeekCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted == true }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    var body: some View {
        let weekStart = TrainingQueries.weekStart(for: .now)
        let thisWeek = sessions.filter { $0.startedAt >= weekStart }
        let target = max(profiles.first?.weeklyWorkoutTarget ?? 3, 1)
        let volume = thisWeek.reduce(0) { $0 + $1.volumeKg }
        Button {
            router.open(.workoutHistory)
        } label: {
            Card {
                CardHeader(title: "Trainingswoche", symbol: "calendar", tint: Theme.training) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(thisWeek.count)")
                        .font(.metricMedium)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("von \(target) Trainings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if volume > 0 {
                        Text("\(Fmt.weightWithUnit(volume, unit: prefs.weightUnit, digits: 0)) Volumen")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                TrainingWeekStrip(sessions: thisWeek)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet den Trainingsverlauf")
    }
}

// MARK: - Kraftentwicklung

/// Dashboard-Karte: Übungen mit der deutlichsten Veränderung des geschätzten 1RM.
struct StrengthCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted == true }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    private struct Trend: Identifiable {
        var id: String
        var exerciseID: String
        var name: String
        var points: [(date: Date, value: Double)]
        var change: Double
        var relative: Double
    }

    private var trends: [Trend] {
        let cutoff = Date.now.adding(days: -56)
        var series: [String: (name: String, exerciseID: String, points: [(date: Date, value: Double)])] = [:]
        for session in sessions where session.startedAt >= cutoff {
            for log in session.exercises {
                guard let best = log.bestEstimatedOneRepMax, best > 0 else { continue }
                let key = "\(log.exerciseID)|\(log.equipmentID ?? "")"
                var entry = series[key] ?? (name: log.exerciseName, exerciseID: log.exerciseID, points: [])
                entry.points.append((session.startedAt, best))
                series[key] = entry
            }
        }
        return series.compactMap { key, entry in
            let sorted = entry.points.sorted { $0.date < $1.date }
            guard sorted.count >= 2, let first = sorted.first, let last = sorted.last, first.value > 0 else { return nil }
            let change = last.value - first.value
            return Trend(id: key, exerciseID: entry.exerciseID, name: entry.name, points: sorted,
                         change: change, relative: change / first.value)
        }
        .sorted { abs($0.relative) > abs($1.relative) }
        .prefix(3)
        .map { $0 }
    }

    var body: some View {
        Card {
            CardHeader(title: "Kraftentwicklung", symbol: "chart.line.uptrend.xyaxis", tint: Theme.training) {
                Text("8 Wochen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let items = trends
            if items.isEmpty {
                Text("Sobald du Übungen mehrfach trainiert hast, siehst du hier, wie sich deine Kraft entwickelt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: Theme.Space.s) {
                    ForEach(items) { trend in
                        Button {
                            router.open(.exercise(id: trend.exerciseID))
                        } label: {
                            HStack(spacing: Theme.Space.s) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(trend.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(Fmt.signed(prefs.weightUnit.fromKg(trend.change), digits: 1)) \(prefs.weightUnit.symbol) geschätztes 1RM")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(trend.change >= 0 ? Theme.positive : .secondary)
                                }
                                Spacer()
                                Chart {
                                    ForEach(Array(trend.points.enumerated()), id: \.offset) { _, point in
                                        LineMark(x: .value("Datum", point.date), y: .value("1RM", point.value))
                                            .foregroundStyle(Theme.training)
                                            .interpolationMethod(.monotone)
                                    }
                                }
                                .chartXAxis(.hidden)
                                .chartYAxis(.hidden)
                                .chartYScale(domain: .automatic(includesZero: false))
                                .chartLegend(.hidden)
                                .frame(width: 72, height: 28)
                                .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Geschätzt nach Epley, getrennt nach Gerät.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
