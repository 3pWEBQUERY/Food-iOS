import Foundation
import SwiftData

/// Gemeinsame Logik rund um Profil, Ziele und Zielwerte.
@MainActor
enum ProfileService {
    /// Aktuellstes Körpergewicht (Messung, sonst Startgewicht).
    static func latestWeightKg(in context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.kg ?? context.currentProfile()?.startWeightKg
    }

    static func energyInputs(for profile: UserProfile, in context: ModelContext) -> EnergyInputs {
        EnergyInputs(profile: profile, currentWeightKg: latestWeightKg(in: context))
    }

    /// Berechnet Zielwerte neu (sofern nicht manuell festgelegt) und übernimmt sie ins Profil.
    @discardableResult
    static func recalculateTargets(for profile: UserProfile, in context: ModelContext, force: Bool = false) -> EnergyResult {
        let inputs = energyInputs(for: profile, in: context)
        let result = EnergyCalculator.compute(inputs, formula: profile.energyFormula, tdeeOverride: profile.adaptiveTDEE)
        if force || !profile.targetsAreManual {
            apply(result, to: profile)
        }
        return result
    }

    static func apply(_ result: EnergyResult, to profile: UserProfile) {
        profile.calorieTarget = result.calorieTarget
        profile.proteinTargetG = result.proteinG
        profile.carbTargetG = result.carbsG
        profile.fatTargetG = result.fatG
        profile.fiberTargetG = result.fiberG
        profile.waterTargetMl = result.waterMl
        profile.updatedAt = .now
    }

    /// Wechselt oder kombiniert Ziele. Beendet die aktuelle Zielphase und beginnt eine neue.
    /// Bestehende Einträge, Trainingshistorie und Messwerte bleiben vollständig erhalten.
    static func changeGoals(_ goals: [FitnessGoal], primary: FitnessGoal, for profile: UserProfile,
                            in context: ModelContext, actor: AuditActor = .user) {
        let previous = profile.primaryGoal
        profile.goals = goals
        profile.primaryGoal = primary
        let result = recalculateTargets(for: profile, in: context)

        let active = (try? context.fetch(FetchDescriptor<GoalPhase>(predicate: #Predicate { $0.endDate == nil }))) ?? []
        for phase in active { phase.endDate = .now }
        let phase = GoalPhase(goals: goals, primary: primary, calorieTarget: result.calorieTarget,
                              proteinTargetG: result.proteinG, startWeightKg: latestWeightKg(in: context),
                              targetWeightKg: profile.targetWeightKg)
        context.insert(phase)
        AuditLog.record(context, actor: actor, summary: "Ziel geändert: \(previous.title) → \(primary.title)",
                        detail: goals.map(\.title).joined(separator: ", "), entityType: EntityType.profile)
        context.saveQuietly()
    }

    /// Aktuelle Zielphase.
    static func activePhase(in context: ModelContext) -> GoalPhase? {
        var d = FetchDescriptor<GoalPhase>(predicate: #Predicate { $0.endDate == nil }, sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
