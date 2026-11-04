import Foundation
import Observation
import SwiftData

/// Verwaltet das laufende Training inklusive Pausentimer.
/// Die ID der aktiven Einheit wird gespeichert, damit ein Training nach einem
/// Neustart der App fortgesetzt werden kann. Funktioniert vollständig offline.
@MainActor
@Observable
final class WorkoutStore {
    private static let activeKey = "kern.workout.activeSession"
    private static let restEndKey = "kern.workout.restEnd"
    private static let restDurationKey = "kern.workout.restDuration"
    private static let restNotificationID = "kern.workout.rest"

    var activeSessionID: UUID? = nil {
        didSet { UserDefaults.standard.set(activeSessionID?.uuidString, forKey: Self.activeKey) }
    }

    /// Ende des laufenden Pausentimers (nil = keine Pause).
    var restEndsAt: Date? = nil {
        didSet {
            if let restEndsAt {
                UserDefaults.standard.set(restEndsAt.timeIntervalSince1970, forKey: Self.restEndKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.restEndKey)
            }
        }
    }

    /// Gesamtdauer der aktuellen Pause (für die Fortschrittsanzeige).
    var restDuration: TimeInterval = 90 {
        didSet { UserDefaults.standard.set(restDuration, forKey: Self.restDurationKey) }
    }

    /// Zählt beendete Pausen – Auslöser für haptisches Feedback.
    var restCompletionCount = 0

    var hasActiveSession: Bool { activeSessionID != nil }

    init() {
        let defaults = UserDefaults.standard
        activeSessionID = defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        let storedEnd = defaults.double(forKey: Self.restEndKey)
        if storedEnd > 0 {
            let end = Date(timeIntervalSince1970: storedEnd)
            restEndsAt = end > .now ? end : nil
        }
        let storedDuration = defaults.double(forKey: Self.restDurationKey)
        restDuration = storedDuration > 0 ? storedDuration : 90
    }

    // MARK: Aktive Einheit

    func activeSession(in context: ModelContext) -> WorkoutSession? {
        guard let id = activeSessionID else { return nil }
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Entfernt eine verwaiste ID (z. B. wenn die Einheit gelöscht wurde). Ausserhalb von `body` aufrufen.
    func validate(in context: ModelContext) {
        guard activeSessionID != nil else { return }
        if let session = activeSession(in: context) {
            if session.isCompleted { activeSessionID = nil }
        } else {
            activeSessionID = nil
        }
    }

    /// Startet ein Training – leer oder aus einer Vorlage. Sätze werden mit den zuletzt
    /// verwendeten Gewichten derselben Übung **und** desselben Geräts vorbefüllt.
    @discardableResult
    func start(template: WorkoutTemplate?, plan: WorkoutPlan?, name: String, in context: ModelContext) -> WorkoutSession {
        if let existing = activeSession(in: context), !existing.isCompleted {
            return existing
        }
        let gymID = AppPreferences.shared.activeGymID.flatMap(UUID.init(uuidString:))
        let resolvedPlan = plan ?? template?.plan
        let session = WorkoutSession(name: name.isEmpty ? "Freies Training" : name,
                                     templateID: template?.id, planID: resolvedPlan?.id, gymID: gymID)
        context.insert(session)

        if let template {
            let deload = resolvedPlan.map { TrainingDeload.isActive(planID: $0.id) } ?? false
            let exercises = TrainingQueries.exerciseMap(in: context)
            for (index, planned) in template.exercises.enumerated() {
                guard let exercise = exercises[planned.exerciseID] else { continue }
                let equipment = planned.equipmentID.flatMap { TrainingQueries.equipment(id: $0, in: context) }
                let log = ExerciseLog(order: index, exerciseID: exercise.id, exerciseName: exercise.name,
                                      equipmentID: equipment?.id, equipmentLabel: equipment?.displayName)
                log.restSeconds = planned.restSeconds
                log.targetRepMin = planned.repMin
                log.targetRepMax = planned.repMax
                log.targetRIR = planned.targetRIR
                log.supersetGroup = planned.supersetGroup
                log.notes = planned.notes
                session.exercises.append(log)

                let workingSets = deload ? max(1, Int((Double(planned.sets) * 0.6).rounded())) : planned.sets
                let targetWeight = TrainingTargetWeights.get(templateID: template.id, exerciseID: exercise.id)
                prefillSets(for: log, workingSets: workingSets, warmups: planned.warmupSets, repMax: planned.repMax,
                            targetWeight: targetWeight, deload: deload, sessionID: session.id, in: context)
                if targetWeight != nil {
                    TrainingTargetWeights.set(nil, templateID: template.id, exerciseID: exercise.id)
                }
            }
        }

        activeSessionID = session.id
        AuditLog.record(context, actor: .user, summary: "Training gestartet: \(session.name)",
                        entityType: EntityType.workout, entityID: session.id.uuidString)
        context.saveQuietly()
        return session
    }

    /// Fügt einer laufenden Einheit eine Übung hinzu.
    @discardableResult
    func addExercise(_ exercise: Exercise, to session: WorkoutSession, sets: Int = 3, in context: ModelContext) -> ExerciseLog {
        let order = (session.exercises.map(\.order).max() ?? -1) + 1
        let log = ExerciseLog(order: order, exerciseID: exercise.id, exerciseName: exercise.name)
        log.restSeconds = AppPreferences.shared.defaultRestSeconds
        session.exercises.append(log)
        prefillSets(for: log, workingSets: sets, warmups: 0, repMax: nil, targetWeight: nil, deload: false,
                    sessionID: session.id, in: context)
        context.saveQuietly()
        return log
    }

    /// Ersetzt eine Übung (z. B. Gerät belegt). Ohne erledigte Sätze wird die Übung direkt getauscht.
    /// Sind bereits Sätze erledigt, bleiben diese erhalten und die neue Übung wird direkt danach eingefügt.
    func swap(_ log: ExerciseLog, to exercise: Exercise, in session: WorkoutSession, in context: ModelContext) {
        if log.sets.contains(where: \.isCompleted) {
            let remaining = max(1, log.sets.filter { !$0.isCompleted && $0.kind != .warmup }.count)
            for later in session.exercises where later.order > log.order { later.order += 1 }
            let replacement = addExercise(exercise, to: session, sets: remaining, in: context)
            replacement.order = log.order + 1
            replacement.restSeconds = log.restSeconds
            replacement.targetRepMin = log.targetRepMin
            replacement.targetRepMax = log.targetRepMax
            replacement.targetRIR = log.targetRIR
            let pending = log.sets.filter { !$0.isCompleted }
            log.sets.removeAll { !$0.isCompleted }
            pending.forEach { context.delete($0) }
        } else {
            let count = max(1, log.sets.filter { $0.kind != .warmup }.count)
            let warmups = log.sets.filter { $0.kind == .warmup }.count
            let old = log.sets
            log.sets.removeAll()
            old.forEach { context.delete($0) }
            log.exerciseID = exercise.id
            log.exerciseName = exercise.name
            log.equipmentID = nil
            log.equipmentLabel = nil
            prefillSets(for: log, workingSets: count, warmups: warmups, repMax: log.targetRepMax, targetWeight: nil,
                        deload: false, sessionID: session.id, in: context)
        }
        context.saveQuietly()
    }

    /// Fügt einen Satz hinzu. Dropsätze starten bei ca. 80 % des letzten Gewichts.
    @discardableResult
    func addSet(to log: ExerciseLog, kind: SetKind, in context: ModelContext) -> SetLog {
        let sorted = log.sortedSets
        let reference = sorted.last { $0.kind != .warmup } ?? sorted.last
        var weight = reference?.weightKg ?? 0
        var reps = reference?.reps ?? 0
        switch kind {
        case .drop:
            weight = TrainingMath.roundWeight(weight * 0.8, step: 1.25)
        case .warmup:
            weight = TrainingMath.roundWeight(weight * 0.5, step: 2.5)
            reps = 8
        default:
            break
        }
        let order: Int
        if kind == .warmup {
            // Aufwärmsätze vor den Arbeitssätzen einordnen.
            let firstWorking = sorted.first { $0.kind != .warmup }?.order ?? (sorted.last?.order ?? -1) + 1
            for set in sorted where set.order >= firstWorking { set.order += 1 }
            order = firstWorking
        } else {
            order = (sorted.last?.order ?? -1) + 1
        }
        let set = SetLog(order: order, kind: kind, weightKg: weight, reps: reps, targetReps: log.targetRepMax)
        log.sets.append(set)
        context.saveQuietly()
        return set
    }

    func deleteSet(_ set: SetLog, from log: ExerciseLog, in context: ModelContext) {
        log.sets.removeAll { $0.id == set.id }
        context.delete(set)
        context.saveQuietly()
    }

    func removeExercise(_ log: ExerciseLog, from session: WorkoutSession, in context: ModelContext) {
        session.exercises.removeAll { $0.id == log.id }
        context.delete(log)
        for (index, item) in session.sortedExercises.enumerated() { item.order = index }
        context.saveQuietly()
    }

    /// Schliesst die Einheit ab. Nicht abgeschlossene Sätze werden verworfen.
    func finish(_ session: WorkoutSession, exertion: Int?, dayForm: Int?, notes: String, in context: ModelContext) {
        session.endedAt = .now
        session.isCompleted = true
        session.perceivedExertion = exertion
        session.dayForm = dayForm
        session.notes = notes

        for log in session.exercises {
            let pending = log.sets.filter { !$0.isCompleted }
            log.sets.removeAll { !$0.isCompleted }
            pending.forEach { context.delete($0) }
        }
        let emptyLogs = session.exercises.filter { $0.sets.isEmpty }
        session.exercises.removeAll { $0.sets.isEmpty }
        emptyLogs.forEach { context.delete($0) }
        for (index, item) in session.sortedExercises.enumerated() { item.order = index }

        if let templateID = session.templateID {
            var descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == templateID })
            descriptor.fetchLimit = 1
            if let template = try? context.fetch(descriptor).first {
                template.lastPerformedAt = .now
            }
        }

        AuditLog.record(context, actor: .user,
                        summary: "Training abgeschlossen: \(session.name)",
                        detail: "\(session.completedSetCount) Sätze · \(Fmt.number(session.volumeKg)) kg Volumen",
                        entityType: EntityType.workout, entityID: session.id.uuidString)
        activeSessionID = nil
        skipRest()
        context.saveQuietly()
        WidgetBridge.refresh(context: context)

        if AppPreferences.shared.healthKitEnabled {
            Task { @MainActor in
                await HealthKitManager.shared.saveWorkout(session)
                context.saveQuietly()
            }
        }
    }

    /// Verwirft die laufende Einheit vollständig.
    func discard(_ session: WorkoutSession, in context: ModelContext) {
        AuditLog.record(context, actor: .user, summary: "Training verworfen: \(session.name)",
                        entityType: EntityType.workout, entityID: session.id.uuidString)
        context.delete(session)
        activeSessionID = nil
        skipRest()
        context.saveQuietly()
    }

    // MARK: Pausentimer

    func startRest(seconds: Int, nextLabel: String? = nil) {
        guard seconds > 0 else { return }
        restDuration = TimeInterval(seconds)
        let end = Date.now.addingTimeInterval(TimeInterval(seconds))
        restEndsAt = end
        scheduleRestNotification(end: end, nextLabel: nextLabel)
    }

    func adjustRest(by delta: TimeInterval) {
        guard let end = restEndsAt else { return }
        let newEnd = end.addingTimeInterval(delta)
        if newEnd <= .now {
            skipRest()
            return
        }
        restEndsAt = newEnd
        restDuration = max(15, restDuration + delta)
        scheduleRestNotification(end: newEnd, nextLabel: nil)
    }

    func skipRest() {
        restEndsAt = nil
        NotificationManager.cancel(prefix: Self.restNotificationID)
    }

    /// Wird von der Oberfläche aufgerufen, wenn die Pause abgelaufen ist.
    func restDidFinish(expectedEnd: Date) {
        guard restEndsAt == expectedEnd else { return }
        restEndsAt = nil
        restCompletionCount += 1
    }

    func restRemaining(at date: Date) -> TimeInterval {
        guard let restEndsAt else { return 0 }
        return max(0, restEndsAt.timeIntervalSince(date))
    }

    private func scheduleRestNotification(end: Date, nextLabel: String?) {
        NotificationManager.cancel(prefix: Self.restNotificationID)
        let body = nextLabel.map { "Weiter mit \($0)." } ?? "Weiter geht es mit dem nächsten Satz."
        NotificationManager.scheduleOnce(id: Self.restNotificationID, title: "Pause vorbei", body: body,
                                         after: end.timeIntervalSinceNow)
    }

    // MARK: Vorbefüllung

    private func prefillSets(for log: ExerciseLog, workingSets: Int, warmups: Int, repMax: Int?, targetWeight: Double?,
                             deload: Bool, sessionID: UUID, in context: ModelContext) {
        let previous = TrainingQueries.lastLog(exerciseID: log.exerciseID, equipmentID: log.equipmentID,
                                               excluding: sessionID, in: context)
        let previousWorking = previous?.sortedSets.filter { $0.kind != .warmup } ?? []
        var order = 0
        let firstWeight = targetWeight ?? previousWorking.first?.weightKg ?? 0
        let baseWeight = deload ? TrainingMath.roundWeight(firstWeight * 0.9, step: 2.5) : firstWeight

        if warmups > 0 && baseWeight > 0 {
            let ratios: [Double] = warmups == 1 ? [0.5] : (warmups == 2 ? [0.4, 0.7] : [0.4, 0.6, 0.8])
            for ratio in ratios.prefix(warmups) {
                let set = SetLog(order: order, kind: .warmup, weightKg: TrainingMath.roundWeight(baseWeight * ratio, step: 2.5), reps: ratio < 0.6 ? 10 : 5)
                log.sets.append(set)
                order += 1
            }
        } else if warmups > 0 {
            for _ in 0..<warmups {
                log.sets.append(SetLog(order: order, kind: .warmup, weightKg: 0, reps: 10))
                order += 1
            }
        }

        for index in 0..<max(workingSets, 1) {
            let source = index < previousWorking.count ? previousWorking[index] : previousWorking.last
            var weight = source?.weightKg ?? 0
            if let targetWeight { weight = targetWeight }
            if deload { weight = TrainingMath.roundWeight(weight * 0.9, step: 2.5) }
            let reps = targetWeight != nil ? 0 : (source?.reps ?? 0)
            let set = SetLog(order: order, kind: .working, weightKg: weight, reps: reps, targetReps: repMax ?? log.targetRepMax)
            log.sets.append(set)
            order += 1
        }
    }
}
