import Foundation
import SwiftData

/// Übung aus der Bibliothek (vordefiniert oder eigene).
@Model
final class Exercise {
    /// Stabile ID, z. B. „barbell-back-squat“ oder eine UUID für eigene Übungen.
    var id: String = UUID().uuidString
    var name: String = ""
    var primaryMuscleRaw: String = MuscleGroup.fullBody.rawValue
    var secondaryMusclesRaw: [String] = []
    var categoryRaw: String = ExerciseCategory.compound.rawValue
    var equipmentKindRaw: String = EquipmentKind.bodyweight.rawValue
    var difficultyRaw: String = Difficulty.beginner.rawValue
    var focusRaw: [String] = []
    var instructions: String = ""
    var cues: [String] = []
    var alternativeIDs: [String] = []
    /// Übung eignet sich als gelenkschonende Variante (angepasstes Training).
    var isJointFriendly: Bool = false
    var isCustom: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    init(id: String, name: String, primary: MuscleGroup, secondary: [MuscleGroup] = [],
         category: ExerciseCategory, equipment: EquipmentKind, difficulty: Difficulty,
         focus: [TrainingFocus] = [.hypertrophy], instructions: String = "", cues: [String] = [],
         alternatives: [String] = [], jointFriendly: Bool = false, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.primaryMuscleRaw = primary.rawValue
        self.secondaryMusclesRaw = secondary.map(\.rawValue)
        self.categoryRaw = category.rawValue
        self.equipmentKindRaw = equipment.rawValue
        self.difficultyRaw = difficulty.rawValue
        self.focusRaw = focus.map(\.rawValue)
        self.instructions = instructions
        self.cues = cues
        self.alternativeIDs = alternatives
        self.isJointFriendly = jointFriendly
        self.isCustom = isCustom
    }

    var primaryMuscle: MuscleGroup { MuscleGroup(rawValue: primaryMuscleRaw) ?? .fullBody }
    var secondaryMuscles: [MuscleGroup] { secondaryMusclesRaw.compactMap(MuscleGroup.init(rawValue:)) }
    var category: ExerciseCategory { ExerciseCategory(rawValue: categoryRaw) ?? .compound }
    var equipmentKind: EquipmentKind { EquipmentKind(rawValue: equipmentKindRaw) ?? .other }
    var difficulty: Difficulty { Difficulty(rawValue: difficultyRaw) ?? .beginner }
    var focus: [TrainingFocus] { focusRaw.compactMap(TrainingFocus.init(rawValue:)) }
    var isBodyweight: Bool { equipmentKind == .bodyweight }
}

/// Konkretes Trainingsgerät (Marke/Modell). Gewichte unterschiedlicher Geräte
/// werden in der Historie nicht als direkt vergleichbar dargestellt.
@Model
final class Equipment {
    var id: String = UUID().uuidString
    var name: String = ""
    var brand: String = ""
    var modelName: String = ""
    var kindRaw: String = EquipmentKind.machine.rawValue
    var exerciseIDs: [String] = []
    /// Kleinste Gewichtsabstufung des Geräts.
    var weightIncrementKg: Double? = nil
    var isCustom: Bool = false
    var notes: String = ""

    init(id: String, name: String, brand: String, modelName: String = "", kind: EquipmentKind,
         exerciseIDs: [String] = [], increment: Double? = nil, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.modelName = modelName
        self.kindRaw = kind.rawValue
        self.exerciseIDs = exerciseIDs
        self.weightIncrementKg = increment
        self.isCustom = isCustom
    }

    var kind: EquipmentKind { EquipmentKind(rawValue: kindRaw) ?? .other }

    var displayName: String {
        [brand, modelName.isEmpty ? name : modelName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Fitnessstudio-Profil mit verfügbaren Geräten.
@Model
final class GymProfile {
    var id: UUID = UUID()
    var name: String = ""
    var equipmentIDs: [String] = []
    var availableKindsRaw: [String] = []
    var preferredExerciseIDs: [String] = []
    var notes: String = ""
    var isDefault: Bool = false
    var createdAt: Date = Date()

    init(name: String, kinds: [EquipmentKind] = EquipmentKind.allCases, isDefault: Bool = false) {
        self.name = name
        self.availableKindsRaw = kinds.map(\.rawValue)
        self.isDefault = isDefault
    }

    var availableKinds: [EquipmentKind] {
        get { availableKindsRaw.compactMap(EquipmentKind.init(rawValue:)) }
        set { availableKindsRaw = newValue.map(\.rawValue) }
    }
}

/// Trainingsplan mit mehreren Trainingstagen (Vorlagen).
@Model
final class WorkoutPlan {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var isActive: Bool = false
    /// "user" | "generated" | "shared"
    var sourceRaw: String = "user"
    var goalRaw: String = FitnessGoal.buildMuscle.rawValue
    var daysPerWeek: Int = 3
    var notes: String = ""
    /// Nachvollziehbare Begründung bei generierten Plänen.
    var rationale: String = ""
    var gymID: UUID? = nil
    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.plan)
    var templates: [WorkoutTemplate] = []

    init(name: String, goal: FitnessGoal, daysPerWeek: Int, source: String = "user") {
        self.name = name
        self.goalRaw = goal.rawValue
        self.daysPerWeek = daysPerWeek
        self.sourceRaw = source
    }

    var sortedTemplates: [WorkoutTemplate] { templates.sorted { $0.order < $1.order } }
    var goal: FitnessGoal { FitnessGoal(rawValue: goalRaw) ?? .buildMuscle }
}

/// Geplante Übung innerhalb einer Vorlage.
struct TemplateExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: String
    var equipmentID: String? = nil
    var sets: Int = 3
    var warmupSets: Int = 0
    var repMin: Int = 8
    var repMax: Int = 12
    var targetRIR: Int? = 2
    var restSeconds: Int = 90
    /// Gleiche Gruppennummer = Supersatz.
    var supersetGroup: Int? = nil
    var notes: String = ""
}

/// Trainingstag/-vorlage, z. B. „Oberkörper A“.
@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    var exercisesData: Data = Data()
    var notes: String = ""
    var lastPerformedAt: Date? = nil
    var plan: WorkoutPlan? = nil

    init(name: String, order: Int = 0, exercises: [TemplateExercise] = []) {
        self.name = name
        self.order = order
        self.exercisesData = ModelCoding.encode(exercises)
    }

    var exercises: [TemplateExercise] {
        get { ModelCoding.decode([TemplateExercise].self, from: exercisesData, default: []) }
        set { exercisesData = ModelCoding.encode(newValue) }
    }
}

/// Durchgeführte Trainingseinheit.
@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var name: String = ""
    var templateID: UUID? = nil
    var planID: UUID? = nil
    var gymID: UUID? = nil
    var notes: String = ""
    /// Subjektive Belastung 1–10 (Session-RPE).
    var perceivedExertion: Int? = nil
    /// Tagesform 1–5.
    var dayForm: Int? = nil
    var isCompleted: Bool = false
    var healthKitUUID: String? = nil
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    var exercises: [ExerciseLog] = []

    init(name: String, startedAt: Date = .now, templateID: UUID? = nil, planID: UUID? = nil, gymID: UUID? = nil) {
        self.name = name
        self.startedAt = startedAt
        self.templateID = templateID
        self.planID = planID
        self.gymID = gymID
    }

    var sortedExercises: [ExerciseLog] { exercises.sorted { $0.order < $1.order } }

    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }

    /// Trainingsvolumen (Arbeitssätze: Gewicht × Wiederholungen).
    var volumeKg: Double {
        exercises.reduce(0) { $0 + $1.volumeKg }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }
}

@Model
final class ExerciseLog {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseID: String = ""
    var exerciseName: String = ""
    var equipmentID: String? = nil
    var equipmentLabel: String? = nil
    var notes: String = ""
    var supersetGroup: Int? = nil
    var restSeconds: Int = 90
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var targetRIR: Int? = nil
    var session: WorkoutSession? = nil
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
    var sets: [SetLog] = []

    init(order: Int, exerciseID: String, exerciseName: String, equipmentID: String? = nil, equipmentLabel: String? = nil) {
        self.order = order
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.equipmentID = equipmentID
        self.equipmentLabel = equipmentLabel
    }

    var sortedSets: [SetLog] { sets.sorted { $0.order < $1.order } }

    var volumeKg: Double {
        sets.filter { $0.isCompleted && $0.kind != .warmup }.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    /// Bester geschätzter 1RM dieser Übung in der Einheit (Epley).
    var bestEstimatedOneRepMax: Double? {
        sets.filter { $0.isCompleted && $0.kind != .warmup && $0.reps > 0 && $0.weightKg > 0 }
            .map { $0.estimatedOneRepMax }
            .max()
    }
}

@Model
final class SetLog {
    var id: UUID = UUID()
    var order: Int = 0
    var kindRaw: String = SetKind.working.rawValue
    var weightKg: Double = 0
    var reps: Int = 0
    var targetReps: Int? = nil
    var rpe: Double? = nil
    var rir: Int? = nil
    var durationSec: Int? = nil
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var exercise: ExerciseLog? = nil

    init(order: Int, kind: SetKind = .working, weightKg: Double = 0, reps: Int = 0, targetReps: Int? = nil) {
        self.order = order
        self.kindRaw = kind.rawValue
        self.weightKg = weightKg
        self.reps = reps
        self.targetReps = targetReps
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    /// Epley-Formel; bei mehr als 12 Wiederholungen nur grob aussagekräftig.
    var estimatedOneRepMax: Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}
