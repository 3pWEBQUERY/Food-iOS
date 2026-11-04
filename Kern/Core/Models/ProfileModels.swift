import Foundation
import SwiftData

/// Persönliches Profil inkl. Ziele und aktueller Zielwerte.
/// Es existiert genau ein Profil pro Gerät/Konto.
@Model
final class UserProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Basisdaten
    var displayName: String = ""
    var birthDate: Date? = nil
    /// Freiwillige Profilangabe – wird nicht für Berechnungen verwendet.
    var genderIdentity: String = ""
    /// Für Energieberechnungen relevante physiologische Angabe.
    var physiologicalSexRaw: String = PhysiologicalSex.unspecified.rawValue
    var heightCm: Double = 170
    var startWeightKg: Double = 70
    var bodyFatPercent: Double? = nil
    var activityLevelRaw: String = ActivityLevel.light.rawValue
    var specialSituationRaw: String = SpecialSituation.none.rawValue

    // Training
    var trainingExperienceRaw: String = TrainingExperience.beginner.rawValue
    var trainingDaysPerWeek: Int = 3
    var sessionDurationMin: Int = 60
    var trainingLocationRaw: String = TrainingLocation.gym.rawValue
    var preferredMethods: [String] = []
    var strengths: String = ""
    var weaknesses: String = ""
    var adaptationsNote: String = ""
    var loadLimitsNote: String = ""
    var excludedExerciseIDs: [String] = []
    var professionalGuidelines: String = ""

    // Ziele
    var goalsRaw: [String] = []
    var primaryGoalRaw: String = FitnessGoal.healthierLife.rawValue
    var targetWeightKg: Double? = nil
    /// Gewünschtes Veränderungstempo in kg pro Woche (Betrag).
    var weeklyRateKg: Double = 0.4

    // Ernährung
    var dietTypeRaw: String = DietType.omnivore.rawValue
    var allergies: [String] = []
    var excludedFoods: [String] = []
    var preferredFoods: [String] = []
    var mealsPerDay: Int = 3
    var wantsRecipes: Bool = false
    var wantsCalorieTarget: Bool = true

    // Zielwerte
    var energyFormulaRaw: String = EnergyFormula.automatic.rawValue
    var calorieTarget: Int = 2000
    var proteinTargetG: Int = 120
    var carbTargetG: Int = 220
    var fatTargetG: Int = 70
    var fiberTargetG: Int = 30
    var waterTargetMl: Int = 2500
    var stepsTarget: Int = 8000
    var weeklyWorkoutTarget: Int = 3
    /// Wurden Zielwerte manuell überschrieben?
    var targetsAreManual: Bool = false
    /// Zuletzt akzeptierte adaptive Schätzung des Gesamtbedarfs.
    var adaptiveTDEE: Double? = nil
    var adaptiveTDEEUpdatedAt: Date? = nil

    init() {}

    // MARK: Abgeleitete Werte

    var physiologicalSex: PhysiologicalSex {
        get { PhysiologicalSex(rawValue: physiologicalSexRaw) ?? .unspecified }
        set { physiologicalSexRaw = newValue.rawValue }
    }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .light }
        set { activityLevelRaw = newValue.rawValue }
    }

    var trainingExperience: TrainingExperience {
        get { TrainingExperience(rawValue: trainingExperienceRaw) ?? .beginner }
        set { trainingExperienceRaw = newValue.rawValue }
    }

    var trainingLocation: TrainingLocation {
        get { TrainingLocation(rawValue: trainingLocationRaw) ?? .gym }
        set { trainingLocationRaw = newValue.rawValue }
    }

    var specialSituation: SpecialSituation {
        get { SpecialSituation(rawValue: specialSituationRaw) ?? .none }
        set { specialSituationRaw = newValue.rawValue }
    }

    var dietType: DietType {
        get { DietType(rawValue: dietTypeRaw) ?? .omnivore }
        set { dietTypeRaw = newValue.rawValue }
    }

    var energyFormula: EnergyFormula {
        get { EnergyFormula(rawValue: energyFormulaRaw) ?? .automatic }
        set { energyFormulaRaw = newValue.rawValue }
    }

    var goals: [FitnessGoal] {
        get { goalsRaw.compactMap(FitnessGoal.init(rawValue:)) }
        set { goalsRaw = newValue.map(\.rawValue) }
    }

    var primaryGoal: FitnessGoal {
        get { FitnessGoal(rawValue: primaryGoalRaw) ?? goals.first ?? .healthierLife }
        set { primaryGoalRaw = newValue.rawValue }
    }

    var age: Int {
        guard let birthDate else { return 30 }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    var hasBirthDate: Bool { birthDate != nil }

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? ""
    }
}

/// Historische Zielphase. Zielwechsel beenden die aktuelle Phase und beginnen eine
/// neue – bestehende Einträge bleiben unverändert erhalten (Abschnitt 3.3).
@Model
final class GoalPhase {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date? = nil
    var goalsRaw: [String] = []
    var primaryGoalRaw: String = FitnessGoal.healthierLife.rawValue
    var calorieTarget: Int = 0
    var proteinTargetG: Int = 0
    var startWeightKg: Double? = nil
    var targetWeightKg: Double? = nil
    var note: String = ""

    init(goals: [FitnessGoal], primary: FitnessGoal, calorieTarget: Int, proteinTargetG: Int,
         startWeightKg: Double?, targetWeightKg: Double?, startDate: Date = .now) {
        self.goalsRaw = goals.map(\.rawValue)
        self.primaryGoalRaw = primary.rawValue
        self.calorieTarget = calorieTarget
        self.proteinTargetG = proteinTargetG
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.startDate = startDate
    }

    var primaryGoal: FitnessGoal { FitnessGoal(rawValue: primaryGoalRaw) ?? .healthierLife }
    var goals: [FitnessGoal] { goalsRaw.compactMap(FitnessGoal.init(rawValue:)) }
    var isActive: Bool { endDate == nil }
}

/// Eigene, tägliche Gewohnheit (Modul „Gewohnheiten“).
@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "checkmark.circle"
    var order: Int = 0
    var createdAt: Date = Date()
    var isArchived: Bool = false

    init(name: String, symbol: String = "checkmark.circle", order: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.order = order
    }
}

@Model
final class HabitCheck {
    var id: UUID = UUID()
    var habitID: UUID = UUID()
    var dayKey: String = ""
    var date: Date = Date()

    init(habitID: UUID, date: Date = .now) {
        self.habitID = habitID
        self.date = date
        self.dayKey = DayKey.make(date)
    }
}

/// Nachvollziehbares Protokoll aller relevanten Datenänderungen (Abschnitt 11.4).
@Model
final class AuditLogEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var actorRaw: String = AuditActor.user.rawValue
    var summary: String = ""
    var detail: String = ""
    var entityType: String = ""
    var entityID: String? = nil
    var isUndoable: Bool = false
    var isUndone: Bool = false

    init(actor: AuditActor, summary: String, detail: String = "", entityType: String, entityID: String?, isUndoable: Bool) {
        self.actorRaw = actor.rawValue
        self.summary = summary
        self.detail = detail
        self.entityType = entityType
        self.entityID = entityID
        self.isUndoable = isUndoable
    }

    var actor: AuditActor { AuditActor(rawValue: actorRaw) ?? .user }
}

enum AuditActor: String, Codable, CaseIterable {
    case user, coach, automation, health, system

    var title: String {
        switch self {
        case .user: "Du"
        case .coach: "KI-Coach"
        case .automation: "Automatisierung"
        case .health: "Apple Health"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .user: "person"
        case .coach: "bubble.left.and.text.bubble.right"
        case .automation: "gearshape.arrow.triangle.2.circlepath"
        case .health: "heart"
        case .system: "gearshape"
        }
    }
}

/// Chat-Verlauf mit dem KI-Coach. Aktionen werden als JSON (`[CoachAction]`) gespeichert.
@Model
final class CoachMessage {
    var id: UUID = UUID()
    var date: Date = Date()
    var roleRaw: String = "user"   // "user" | "assistant"
    var text: String = ""
    var actionsData: Data = Data()
    var quickReplies: [String] = []
    @Attribute(.externalStorage) var imageData: Data? = nil

    init(role: String, text: String, date: Date = .now) {
        self.roleRaw = role
        self.text = text
        self.date = date
    }

    var isUser: Bool { roleRaw == "user" }
}
