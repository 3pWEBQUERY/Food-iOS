import Foundation

/// Trainingsaufteilung.
enum TrainingSplit: String, Hashable {
    case fullBody, fullBodyAB, fullBodyABC, pushPullLegs, upperLower, hybrid, pushPullLegsTwice

    var title: String {
        switch self {
        case .fullBody: "Ganzkörper"
        case .fullBodyAB: "Ganzkörper A/B"
        case .fullBodyABC: "Ganzkörper A/B/C"
        case .pushPullLegs: "Push / Pull / Beine"
        case .upperLower: "Oberkörper / Unterkörper"
        case .hybrid: "Push / Pull / Beine + Ober-/Unterkörper"
        case .pushPullLegsTwice: "Push / Pull / Beine (2×)"
        }
    }
}

/// Eingaben für die regelbasierte Planerstellung.
struct TrainingPlanOptions: Hashable {
    var daysPerWeek: Int
    var sessionMinutes: Int
    var focus: TrainingFocus
    var experience: TrainingExperience
    var goal: FitnessGoal
    var preferJointFriendly: Bool
    var availableKinds: Set<EquipmentKind>
    var excludedExerciseIDs: Set<String>
    var gymName: String?
}

struct TrainingPlanDraftDay: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var exercises: [TemplateExercise]
    var estimatedMinutes: Int
}

struct TrainingPlanDraft: Hashable {
    var name: String
    var split: TrainingSplit
    var options: TrainingPlanOptions
    var days: [TrainingPlanDraftDay]
    var rationale: [String]
    /// Arbeitssätze pro Woche je Hauptmuskelgruppe.
    var weeklySets: [(muscle: MuscleGroup, sets: Int)]

    static func == (lhs: TrainingPlanDraft, rhs: TrainingPlanDraft) -> Bool {
        lhs.name == rhs.name && lhs.days == rhs.days && lhs.rationale == rhs.rationale
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(days)
    }
}

/// Erstellt Trainingspläne aus nachvollziehbaren Regeln (keine freie KI-Generierung).
/// Die Begründung wird mitgeliefert, damit jede Entscheidung überprüfbar bleibt.
enum PlanGenerator {
    /// Bewegungsmuster mit bevorzugten Übungen (in Reihenfolge der Eignung).
    enum Pattern: Hashable {
        case squat, hinge, horizontalPress, inclinePress, verticalPress, verticalPull, horizontalPull,
             lateralRaise, rearDelt, chestIso, quadIso, hamIso, glute, lunge, biceps, triceps, calves, core

        var preferred: [String] {
            switch self {
            case .squat: ["back-squat", "leg-press", "goblet-squat", "hack-squat", "smith-squat", "bodyweight-squat"]
            case .hinge: ["romanian-deadlift", "trap-bar-deadlift", "dumbbell-rdl", "deadlift", "hip-thrust", "back-extension"]
            case .horizontalPress: ["barbell-bench-press", "dumbbell-bench-press", "machine-chest-press", "smith-bench-press", "push-up"]
            case .inclinePress: ["incline-dumbbell-press", "incline-barbell-bench-press", "smith-incline-press", "machine-chest-press", "push-up"]
            case .verticalPress: ["overhead-press", "dumbbell-shoulder-press", "machine-shoulder-press", "arnold-press"]
            case .verticalPull: ["pull-up", "lat-pulldown", "assisted-pull-up", "close-grip-pulldown", "chin-up", "inverted-row"]
            case .horizontalPull: ["barbell-row", "seated-cable-row", "dumbbell-row", "machine-row", "t-bar-row", "inverted-row"]
            case .lateralRaise: ["lateral-raise", "cable-lateral-raise", "machine-lateral-raise"]
            case .rearDelt: ["face-pull", "reverse-pec-deck", "rear-delt-fly", "band-pull-apart"]
            case .chestIso: ["cable-fly", "pec-deck", "dumbbell-fly", "push-up"]
            case .quadIso: ["leg-extension", "step-up", "bodyweight-squat"]
            case .hamIso: ["lying-leg-curl", "seated-leg-curl", "dumbbell-rdl", "nordic-curl"]
            case .glute: ["hip-thrust", "hip-thrust-machine", "glute-bridge", "cable-kickback", "hip-abduction-machine"]
            case .lunge: ["bulgarian-split-squat", "walking-lunge", "step-up", "leg-press"]
            case .biceps: ["dumbbell-curl", "cable-curl", "barbell-curl", "hammer-curl", "preacher-curl-machine"]
            case .triceps: ["triceps-pushdown", "overhead-cable-extension", "dumbbell-overhead-extension", "skull-crusher", "bench-dip"]
            case .calves: ["standing-calf-raise", "seated-calf-raise", "leg-press-calf-raise"]
            case .core: ["plank", "dead-bug", "pallof-press", "cable-crunch", "side-plank", "hanging-leg-raise"]
            }
        }

        var isCompound: Bool {
            switch self {
            case .squat, .hinge, .horizontalPress, .inclinePress, .verticalPress, .verticalPull, .horizontalPull, .lunge: true
            default: false
            }
        }
    }

    private struct Slot {
        var pattern: Pattern
        var variant: Int = 0
    }

    private struct DayBlueprint {
        var name: String
        var slots: [Slot]
    }

    static func defaultFocus(for goal: FitnessGoal) -> TrainingFocus {
        switch goal {
        case .strengthEndurance: .strength
        case .adaptedTraining, .rehabilitation: .endurance
        default: .hypertrophy
        }
    }

    static func split(for days: Int, experience: TrainingExperience, focus: TrainingFocus) -> TrainingSplit {
        switch days {
        case ...1: return .fullBody
        case 2: return .fullBodyAB
        case 3: return (experience == .advanced && focus == .hypertrophy) ? .pushPullLegs : .fullBodyABC
        case 4: return .upperLower
        case 5: return .hybrid
        default: return .pushPullLegsTwice
        }
    }

    // MARK: Generierung

    static func generate(options: TrainingPlanOptions, exercises: [Exercise]) -> TrainingPlanDraft {
        let split = split(for: options.daysPerWeek, experience: options.experience, focus: options.focus)
        let blueprints = blueprints(for: split)
        let perDay = exerciseCount(for: options.sessionMinutes)

        var usedAcrossPlan: [String: Int] = [:]
        var days: [TrainingPlanDraftDay] = []
        for blueprint in blueprints {
            var slots = blueprint.slots
            if slots.count < perDay {
                let extras: [Slot] = [Slot(pattern: .core), Slot(pattern: .calves), Slot(pattern: .rearDelt), Slot(pattern: .core, variant: 1)]
                slots += extras.prefix(perDay - slots.count)
            }
            slots = Array(slots.prefix(perDay))

            var usedToday = Set<String>()
            var items: [TemplateExercise] = []
            var firstCompoundDone = false
            for slot in slots {
                guard let exercise = pick(slot, exercises: exercises, options: options, excluded: usedToday,
                                          usage: usedAcrossPlan) else { continue }
                usedToday.insert(exercise.id)
                usedAcrossPlan[exercise.id, default: 0] += 1
                var item = prescription(for: exercise, pattern: slot.pattern, options: options)
                if slot.pattern.isCompound && !firstCompoundDone && exercise.category == .compound {
                    item.warmupSets = options.experience == .advanced ? 3 : 2
                    if options.experience == .none || options.experience == .beginner { item.warmupSets = 1 }
                    firstCompoundDone = true
                }
                items.append(item)
            }
            days.append(TrainingPlanDraftDay(name: blueprint.name, exercises: items, estimatedMinutes: estimateMinutes(items)))
        }

        // Volumen pro Muskelgruppe
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var volume: [MuscleGroup: Int] = [:]
        for day in days {
            for item in day.exercises {
                guard let exercise = byID[item.exerciseID] else { continue }
                volume[exercise.primaryMuscle, default: 0] += item.sets
            }
        }
        let weeklySets = volume.sorted { $0.value > $1.value }.map { (muscle: $0.key, sets: $0.value) }

        let rationale = makeRationale(split: split, options: options, days: days, weeklySets: weeklySets)
        let name: String = switch options.focus {
        case .strength: "Kraftplan · \(split.title)"
        case .hypertrophy: "Muskelaufbau · \(split.title)"
        case .endurance: "Kraftausdauer · \(split.title)"
        case .mobility: "Mobilität & Kraft · \(split.title)"
        }
        return TrainingPlanDraft(name: name, split: split, options: options, days: days, rationale: rationale, weeklySets: weeklySets)
    }

    private static func blueprints(for split: TrainingSplit) -> [DayBlueprint] {
        let fullA = DayBlueprint(name: "Ganzkörper A", slots: [
            Slot(pattern: .squat), Slot(pattern: .horizontalPress), Slot(pattern: .horizontalPull),
            Slot(pattern: .hinge), Slot(pattern: .lateralRaise), Slot(pattern: .core)])
        let fullB = DayBlueprint(name: "Ganzkörper B", slots: [
            Slot(pattern: .hinge, variant: 1), Slot(pattern: .verticalPull), Slot(pattern: .verticalPress),
            Slot(pattern: .lunge), Slot(pattern: .biceps), Slot(pattern: .triceps)])
        let fullC = DayBlueprint(name: "Ganzkörper C", slots: [
            Slot(pattern: .squat, variant: 1), Slot(pattern: .inclinePress), Slot(pattern: .horizontalPull, variant: 1),
            Slot(pattern: .glute), Slot(pattern: .rearDelt), Slot(pattern: .calves)])
        let upperA = DayBlueprint(name: "Oberkörper A", slots: [
            Slot(pattern: .horizontalPress), Slot(pattern: .horizontalPull), Slot(pattern: .verticalPress),
            Slot(pattern: .verticalPull), Slot(pattern: .triceps), Slot(pattern: .biceps)])
        let upperB = DayBlueprint(name: "Oberkörper B", slots: [
            Slot(pattern: .inclinePress), Slot(pattern: .verticalPull, variant: 1), Slot(pattern: .horizontalPull, variant: 1),
            Slot(pattern: .lateralRaise), Slot(pattern: .chestIso), Slot(pattern: .rearDelt)])
        let lowerA = DayBlueprint(name: "Unterkörper A", slots: [
            Slot(pattern: .squat), Slot(pattern: .hinge), Slot(pattern: .quadIso),
            Slot(pattern: .hamIso), Slot(pattern: .calves), Slot(pattern: .core)])
        let lowerB = DayBlueprint(name: "Unterkörper B", slots: [
            Slot(pattern: .hinge, variant: 1), Slot(pattern: .lunge), Slot(pattern: .glute),
            Slot(pattern: .hamIso, variant: 1), Slot(pattern: .calves, variant: 1), Slot(pattern: .core, variant: 1)])
        let push = DayBlueprint(name: "Push", slots: [
            Slot(pattern: .horizontalPress), Slot(pattern: .verticalPress), Slot(pattern: .inclinePress),
            Slot(pattern: .lateralRaise), Slot(pattern: .chestIso), Slot(pattern: .triceps)])
        let pull = DayBlueprint(name: "Pull", slots: [
            Slot(pattern: .verticalPull), Slot(pattern: .horizontalPull), Slot(pattern: .horizontalPull, variant: 1),
            Slot(pattern: .rearDelt), Slot(pattern: .biceps), Slot(pattern: .biceps, variant: 1)])
        let legs = DayBlueprint(name: "Beine", slots: [
            Slot(pattern: .squat), Slot(pattern: .hinge), Slot(pattern: .lunge),
            Slot(pattern: .quadIso), Slot(pattern: .hamIso), Slot(pattern: .calves)])

        switch split {
        case .fullBody:
            var single = fullA
            single.name = "Ganzkörper"
            single.slots = [Slot(pattern: .squat), Slot(pattern: .horizontalPress), Slot(pattern: .verticalPull),
                            Slot(pattern: .hinge), Slot(pattern: .verticalPress), Slot(pattern: .horizontalPull), Slot(pattern: .core)]
            return [single]
        case .fullBodyAB: return [fullA, fullB]
        case .fullBodyABC: return [fullA, fullB, fullC]
        case .pushPullLegs: return [push, pull, legs]
        case .upperLower: return [upperA, lowerA, upperB, lowerB]
        case .hybrid:
            var upper = upperA
            upper.name = "Oberkörper"
            var lower = lowerB
            lower.name = "Unterkörper"
            return [push, pull, legs, upper, lower]
        case .pushPullLegsTwice:
            func variant(_ day: DayBlueprint, _ suffix: String) -> DayBlueprint {
                DayBlueprint(name: "\(day.name) \(suffix)", slots: day.slots.map { Slot(pattern: $0.pattern, variant: $0.variant + 1) })
            }
            var pushA = push; pushA.name = "Push A"
            var pullA = pull; pullA.name = "Pull A"
            var legsA = legs; legsA.name = "Beine A"
            return [pushA, pullA, legsA, variant(push, "B"), variant(pull, "B"), variant(legs, "B")]
        }
    }

    private static func exerciseCount(for minutes: Int) -> Int {
        switch minutes {
        case ..<35: 4
        case ..<50: 5
        case ..<70: 6
        default: 7
        }
    }

    /// Wählt die passende Übung für ein Bewegungsmuster.
    private static func pick(_ slot: Slot, exercises: [Exercise], options: TrainingPlanOptions,
                             excluded: Set<String>, usage: [String: Int]) -> Exercise? {
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allowedDifficulty: Set<Difficulty> = switch options.experience {
        case .none, .beginner: [.beginner, .intermediate]
        case .intermediate: [.beginner, .intermediate]
        case .advanced: Set(Difficulty.allCases)
        }
        let candidates = slot.pattern.preferred.compactMap { byID[$0] }.filter { exercise in
            !options.excludedExerciseIDs.contains(exercise.id)
                && !excluded.contains(exercise.id)
                && (exercise.isBodyweight || options.availableKinds.contains(exercise.equipmentKind))
                && allowedDifficulty.contains(exercise.difficulty)
        }
        var ranked = candidates
        if options.preferJointFriendly {
            ranked = candidates.filter(\.isJointFriendly) + candidates.filter { !$0.isJointFriendly }
        } else if options.experience == .none {
            // Ganz neue Trainierende: geführte Bewegungen zuerst.
            ranked = candidates.filter { $0.equipmentKind == .machine || $0.equipmentKind == .cable }
                + candidates.filter { $0.equipmentKind != .machine && $0.equipmentKind != .cable }
        }
        guard !ranked.isEmpty else { return nil }
        // Varianten bevorzugen bisher wenig genutzte Übungen.
        let sortedByUsage = ranked.enumerated().sorted { lhs, rhs in
            let l = usage[lhs.element.id, default: 0], r = usage[rhs.element.id, default: 0]
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
        if slot.variant == 0 { return ranked.first }
        return sortedByUsage[min(slot.variant, sortedByUsage.count - 1)]
    }

    /// Sätze, Wiederholungen, RIR und Pausen nach Ziel und Erfahrung.
    private static func prescription(for exercise: Exercise, pattern: Pattern, options: TrainingPlanOptions) -> TemplateExercise {
        let compound = exercise.category == .compound
        var item = TemplateExercise(exerciseID: exercise.id)
        switch options.experience {
        case .none, .beginner: item.sets = compound ? 3 : 2
        case .intermediate: item.sets = 3
        case .advanced: item.sets = compound ? 4 : 3
        }
        switch options.focus {
        case .strength:
            (item.repMin, item.repMax, item.restSeconds) = compound ? (4, 6, 180) : (8, 12, 90)
        case .hypertrophy:
            (item.repMin, item.repMax, item.restSeconds) = compound ? (6, 10, 120) : (10, 15, 75)
        case .endurance, .mobility:
            (item.repMin, item.repMax, item.restSeconds) = compound ? (12, 15, 75) : (15, 20, 60)
        }
        if exercise.category == .core {
            (item.repMin, item.repMax, item.restSeconds) = (10, 15, 60)
        }
        item.targetRIR = switch options.experience {
        case .none, .beginner: 3
        case .intermediate: 2
        case .advanced: 1
        }
        if options.preferJointFriendly {
            item.targetRIR = max(item.targetRIR ?? 2, 3)
            item.restSeconds += 30
        }
        return item
    }

    private static func estimateMinutes(_ items: [TemplateExercise]) -> Int {
        let seconds = items.reduce(0) { total, item in
            total + (item.sets + item.warmupSets) * (45 + item.restSeconds)
        }
        return Int((Double(seconds) / 60).rounded()) + 5
    }

    private static func makeRationale(split: TrainingSplit, options: TrainingPlanOptions, days: [TrainingPlanDraftDay],
                                      weeklySets: [(muscle: MuscleGroup, sets: Int)]) -> [String] {
        var lines: [String] = []
        let splitReason: String = switch split {
        case .fullBody: "Bei einem Trainingstag pro Woche deckt ein Ganzkörpertraining alle grossen Muskelgruppen ab."
        case .fullBodyAB: "Zwei Ganzkörpertage (A/B) trainieren jede Muskelgruppe zweimal pro Woche – effizient bei wenig Zeit."
        case .fullBodyABC: "Drei Ganzkörpertage (A/B/C) verteilen das Volumen gleichmässig und trainieren jede Muskelgruppe mehrmals pro Woche."
        case .pushPullLegs: "Mit deiner Erfahrung erlaubt Push/Pull/Beine mehr Volumen pro Einheit bei ausreichender Erholung."
        case .upperLower: "Vier Tage Ober-/Unterkörper: jede Muskelgruppe zweimal pro Woche bei moderater Dauer pro Einheit."
        case .hybrid: "Fünf Tage kombinieren Push/Pull/Beine mit einem Ober- und Unterkörpertag – hohe Frequenz, gut steuerbar."
        case .pushPullLegsTwice: "Sechs Tage Push/Pull/Beine im Wechsel – nur bei guter Regeneration empfehlenswert."
        }
        lines.append(splitReason)

        let focusReason: String = switch options.focus {
        case .strength: "Fokus Maximalkraft: Grundübungen mit 4–6 Wiederholungen und längeren Pausen, Ergänzungsübungen im mittleren Bereich."
        case .hypertrophy: "Fokus Muskelaufbau: Grundübungen mit 6–10, Isolationsübungen mit 10–15 Wiederholungen."
        case .endurance: "Fokus Kraftausdauer: 12–20 Wiederholungen mit kürzeren Pausen."
        case .mobility: "Fokus Mobilität: moderate Lasten, höhere Wiederholungen, gelenkschonende Ausführung."
        }
        lines.append(focusReason)

        let rir: String = switch options.experience {
        case .none, .beginner: "3 Wiederholungen Reserve (RIR 3) – Technik vor Gewicht."
        case .intermediate: "2 Wiederholungen Reserve (RIR 2)."
        case .advanced: "1 Wiederholung Reserve (RIR 1) bei Arbeitssätzen."
        }
        lines.append("Intensität: \(rir) Gewichte steigerst du, sobald du die obere Wiederholungszahl in allen Sätzen schaffst.")

        if let gym = options.gymName {
            lines.append("Übungen passend zur Ausstattung von „\(gym)“ ausgewählt.")
        }
        if options.preferJointFriendly {
            lines.append("Gelenkschonende Varianten wurden bevorzugt, mit etwas mehr Reserve und längeren Pausen.")
        }
        if !options.excludedExerciseIDs.isEmpty {
            lines.append("\(options.excludedExerciseIDs.count) Übung(en) hast du ausgeschlossen – sie werden nicht verwendet.")
        }
        let avg = days.isEmpty ? 0 : days.map(\.estimatedMinutes).reduce(0, +) / days.count
        lines.append("Geschätzte Dauer: ca. \(avg) Minuten pro Einheit inklusive Aufwärmen.")
        if let top = weeklySets.first {
            lines.append("Wöchentliches Volumen: \(weeklySets.map { "\($0.muscle.title) \($0.sets)" }.prefix(6).joined(separator: ", ")) Sätze. Am meisten: \(top.muscle.title).")
        }
        return lines
    }
}
