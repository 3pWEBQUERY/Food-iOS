import Foundation
import SwiftData
import WidgetKit

/// Verbindet App-Daten mit den Widgets: schreibt den Tages-Schnappschuss in die App Group
/// und übernimmt ausstehende Widget-Aktionen (z. B. Wasser) als echte Einträge.
@MainActor
enum WidgetBridge {
    static func refresh(context: ModelContext) {
        let prefs = AppPreferences.shared
        let key = DayKey.today

        let foods = (try? context.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.dayKey == key }))) ?? []
        let totals = foods.reduce(Nutrients.zero) { $0 + $1.nutrients }
        let water = ((try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.dayKey == key }))) ?? [])
            .reduce(0) { $0 + $1.ml }

        let profile = context.currentProfile()

        let start = Date.now.adding(days: -30)
        var weightDescriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.date >= start },
                                                            sortBy: [SortDescriptor(\.date, order: .reverse)])
        weightDescriptor.fetchLimit = 120
        let weights = (try? context.fetch(weightDescriptor)) ?? []
        let latest = weights.first?.kg ?? ProfileService.latestWeightKg(in: context)
        let trend = AdaptiveEnergyEstimator.weeklyTrend(weights.map { (date: $0.date, kg: $0.kg) })

        let next = nextWorkout(in: context)

        let snapshot = WidgetSnapshot(
            date: .now,
            kcalConsumed: totals.kcal,
            kcalTarget: Double(profile?.calorieTarget ?? 2000),
            proteinConsumed: totals.protein,
            proteinTarget: Double(profile?.proteinTargetG ?? 120),
            carbsConsumed: totals.carbs,
            carbsTarget: Double(profile?.carbTargetG ?? 220),
            fatConsumed: totals.fat,
            fatTarget: Double(profile?.fatTargetG ?? 70),
            waterMl: water,
            waterTargetMl: Double(profile?.waterTargetMl ?? 2500),
            latestWeightKg: latest,
            weightTrendKgPerWeek: trend,
            weightUnit: prefs.weightUnit.rawValue,
            energyUnit: prefs.energyUnit.rawValue,
            nextWorkoutName: next?.name,
            nextWorkoutDetail: next?.detail
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Übernimmt Aktionen aus Widgets (nicht aus `refresh` aufrufen, um Schleifen zu vermeiden).
    static func ingestPendingActions(context: ModelContext) {
        let additions = WidgetPendingActions.takeWater()
        guard !additions.isEmpty else { return }
        for addition in additions {
            LogService.logWater(ml: addition.ml, date: addition.date, source: .widget, actor: .automation, in: context)
        }
    }

    /// Nächste Einheit aus dem aktiven Plan: die am längsten nicht durchgeführte Vorlage.
    private static func nextWorkout(in context: ModelContext) -> (name: String, detail: String)? {
        let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>(predicate: #Predicate { $0.isActive == true }))) ?? []
        guard let plan = plans.first else { return nil }
        let templates = plan.sortedTemplates
        guard !templates.isEmpty else { return nil }
        let next = templates.min { lhs, rhs in
            switch (lhs.lastPerformedAt, rhs.lastPerformedAt) {
            case (nil, nil): return lhs.order < rhs.order
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?): return l < r
            }
        }
        guard let next else { return nil }
        let count = next.exercises.count
        return (next.name, "\(count) \(count == 1 ? "Übung" : "Übungen") · \(plan.name)")
    }
}
