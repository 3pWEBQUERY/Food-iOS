import Foundation
import SwiftData

/// Nachvollziehbarer Progressionsvorschlag. Wird nie automatisch angewendet.
struct TrainingSuggestion: Identifiable, Hashable {
    enum Kind: Hashable {
        case increase(newWeightKg: Double)
        case holdOrReduce(newWeightKg: Double)
        case deload
    }

    /// Stabil pro Datenlage – neue Trainingsdaten erzeugen einen neuen Vorschlag.
    var id: String
    var kind: Kind
    var planID: UUID
    var templateID: UUID?
    var exerciseID: String?
    var title: String
    var reason: String

    var symbol: String {
        switch kind {
        case .increase: "arrow.up.right"
        case .holdOrReduce: "equal"
        case .deload: "leaf"
        }
    }
}

/// Doppelte Progression: zuerst Wiederholungen bis zur Obergrenze steigern, dann das Gewicht.
enum ProgressionAdvisor {
    private static let dismissedKey = "kern.training.dismissedSuggestions"

    static func suggestions(for plan: WorkoutPlan, in context: ModelContext) -> [TrainingSuggestion] {
        let planID: UUID? = plan.id
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.isCompleted == true && $0.planID == planID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let dismissed = dismissedIDs()
        var result: [TrainingSuggestion] = []

        if let deload = deloadSuggestion(plan: plan, sessions: sessions), !dismissed.contains(deload.id),
           !TrainingDeload.isActive(planID: plan.id) {
            result.append(deload)
        }

        let equipmentList = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        for template in plan.sortedTemplates {
            let templateSessions = sessions.filter { $0.templateID == template.id }
            guard templateSessions.count >= 2 else { continue }
            for planned in template.exercises {
                let logs = templateSessions.compactMap { session in
                    session.exercises.first { $0.exerciseID == planned.exerciseID && $0.equipmentID == planned.equipmentID }
                }
                guard logs.count >= 2 else { continue }
                let recent = Array(logs.prefix(2))
                let working = recent.map { $0.sets.filter { $0.isCompleted && $0.kind == .working } }
                guard working.allSatisfy({ !$0.isEmpty }) else { continue }
                let topWeight = working[0].map(\.weightKg).max() ?? 0
                guard topWeight > 0 else { continue }
                let previousTop = working[1].map(\.weightKg).max() ?? 0
                let name = exercises.first { $0.id == planned.exerciseID }?.name ?? recent[0].exerciseName
                let kind = exercises.first { $0.id == planned.exerciseID }?.equipmentKind ?? .other
                let equipment = planned.equipmentID.flatMap { id in equipmentList.first { $0.id == id } }
                let latestSessionID = templateSessions.first?.id.uuidString ?? ""

                let hitTop = working.allSatisfy { sets in
                    sets.allSatisfy { set in
                        set.reps >= planned.repMax && (set.rir ?? Int.max) >= (planned.targetRIR ?? 0)
                    }
                }
                let missedBottom = working.allSatisfy { sets in sets.contains { $0.reps < planned.repMin } }

                if hitTop && topWeight >= previousTop {
                    let step = TrainingMath.increment(for: kind, equipment: equipment)
                    let next = topWeight + step
                    let id = "inc|\(template.id.uuidString)|\(planned.exerciseID)|\(latestSessionID)"
                    guard !dismissed.contains(id) else { continue }
                    result.append(TrainingSuggestion(
                        id: id, kind: .increase(newWeightKg: next), planID: plan.id, templateID: template.id,
                        exerciseID: planned.exerciseID,
                        title: "\(name): auf \(Fmt.decimal(next, maxDigits: 2)) kg steigern",
                        reason: "In den letzten zwei Einheiten hast du in allen Arbeitssätzen \(planned.repMax) Wiederholungen mit \(Fmt.decimal(topWeight, maxDigits: 2)) kg erreicht. Vorschlag: \(Fmt.decimal(step, maxDigits: 2)) kg mehr und wieder bei \(planned.repMin) Wiederholungen beginnen."
                    ))
                } else if missedBottom {
                    let reduced = TrainingMath.roundWeight(topWeight * 0.95, step: TrainingMath.increment(for: kind, equipment: equipment) / 2)
                    let id = "hold|\(template.id.uuidString)|\(planned.exerciseID)|\(latestSessionID)"
                    guard !dismissed.contains(id) else { continue }
                    result.append(TrainingSuggestion(
                        id: id, kind: .holdOrReduce(newWeightKg: reduced), planID: plan.id, templateID: template.id,
                        exerciseID: planned.exerciseID,
                        title: "\(name): Gewicht halten oder leicht reduzieren",
                        reason: "Zweimal in Folge lag mindestens ein Satz unter \(planned.repMin) Wiederholungen. Bleib bei \(Fmt.decimal(topWeight, maxDigits: 2)) kg oder versuche \(Fmt.decimal(reduced, maxDigits: 2)) kg (−5 %), um wieder sauber in den Zielbereich zu kommen."
                    ))
                }
            }
        }
        return result
    }

    /// Leichtere Woche bei anhaltend hoher Belastung oder sinkender Leistung.
    private static func deloadSuggestion(plan: WorkoutPlan, sessions: [WorkoutSession]) -> TrainingSuggestion? {
        let lastThree = Array(sessions.prefix(3))
        guard lastThree.count == 3 else { return nil }
        let latestID = lastThree[0].id.uuidString

        let highEffort = lastThree.allSatisfy { ($0.perceivedExertion ?? 0) >= 9 }
        if highEffort {
            return TrainingSuggestion(
                id: "deload|rpe|\(plan.id.uuidString)|\(latestID)", kind: .deload, planID: plan.id,
                title: "Leichtere Trainingswoche einplanen",
                reason: "Deine letzten drei Einheiten hast du mit einer Belastung von 9 oder 10 bewertet. Eine Woche mit rund 40 % weniger Sätzen und etwas weniger Gewicht kann die Regeneration unterstützen."
            )
        }

        // Leistungsabfall: bester e1RM der Hauptübung sinkt dreimal in Folge
        var declining = false
        var exerciseName = ""
        if let first = lastThree.last?.sortedExercises.first {
            let values = lastThree.reversed().compactMap { session in
                session.exercises.first { $0.exerciseID == first.exerciseID && $0.equipmentID == first.equipmentID }?.bestEstimatedOneRepMax
            }
            if values.count == 3, values[0] > values[1], values[1] > values[2], (values[0] - values[2]) / values[0] > 0.05 {
                declining = true
                exerciseName = first.exerciseName
            }
        }
        guard declining else { return nil }
        return TrainingSuggestion(
            id: "deload|drop|\(plan.id.uuidString)|\(latestID)", kind: .deload, planID: plan.id,
            title: "Leichtere Trainingswoche einplanen",
            reason: "Deine geschätzte Maximalkraft bei \(exerciseName) ist über drei Einheiten gesunken. Das kann auf Erholungsbedarf hinweisen – eine Ursache lässt sich daraus nicht sicher ableiten. Eine leichtere Woche ist ein einfacher Test."
        )
    }

    // MARK: Annehmen / Ablehnen

    @MainActor
    static func accept(_ suggestion: TrainingSuggestion, in context: ModelContext) {
        switch suggestion.kind {
        case .increase(let weight), .holdOrReduce(let weight):
            if let templateID = suggestion.templateID, let exerciseID = suggestion.exerciseID {
                TrainingTargetWeights.set(weight, templateID: templateID, exerciseID: exerciseID)
            }
        case .deload:
            TrainingDeload.start(planID: suggestion.planID)
        }
        markHandled(suggestion)
        AuditLog.record(context, actor: .user, summary: "Trainingsvorschlag angenommen: \(suggestion.title)",
                        entityType: EntityType.plan, entityID: suggestion.planID.uuidString)
        context.saveQuietly()
    }

    static func dismiss(_ suggestion: TrainingSuggestion) {
        markHandled(suggestion)
    }

    private static func markHandled(_ suggestion: TrainingSuggestion) {
        var ids = dismissedIDs()
        ids.insert(suggestion.id)
        UserDefaults.standard.set(Array(ids.suffix(300)), forKey: dismissedKey)
    }

    private static func dismissedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }
}
