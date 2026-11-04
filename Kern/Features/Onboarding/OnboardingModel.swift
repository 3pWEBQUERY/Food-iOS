import Foundation
import Observation
import SwiftData

/// Entwurf aller Onboarding-Angaben. Erst beim Abschluss wird das Profil gespeichert.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Hashable {
        case welcome, goals, aboutYou, activity, goalDetails, nutrition, modules, summary
    }

    var step: Step = .welcome
    var isGuest = false
    var appleUserID: String?

    // Ziele
    var goals: [FitnessGoal] = []
    var primaryGoal: FitnessGoal?

    // Basisdaten
    var name = ""
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var hasBirthDate = true
    var sex: PhysiologicalSex = .unspecified
    var genderIdentity = ""
    var heightCm: Double = 172
    var weightInput: Double = 75
    var bodyFatPercent: Double?
    var weightUnit: WeightUnit = .kg
    var energyUnit: EnergyUnit = .kcal
    var specialSituation: SpecialSituation = .none

    // Aktivität & Training
    var activity: ActivityLevel = .light
    var experience: TrainingExperience = .beginner
    var trainingDays = 3
    var sessionMinutes = 60
    var location: TrainingLocation = .gym
    var preferredMethods: Set<String> = []
    var strengths = ""
    var weaknesses = ""
    var adaptationsNote = ""
    var loadLimitsNote = ""
    var excludedExercises = ""
    var professionalGuidelines = ""

    // Ziel-Details
    var targetWeightInput: Double?
    var weeklyRateKg: Double = 0.4

    // Ernährung
    var diet: DietType = .omnivore
    var allergies: Set<String> = []
    var excludedFoods = ""
    var preferredFoods = ""
    var mealsPerDay = 3
    var wantsRecipes = false
    var wantsCalorieTarget = true

    // Module
    var modules: Set<AppModule> = [.nutrition, .water, .training, .measurements]
    private var modulesTouched = false

    static let methodOptions = ["Freie Gewichte", "Maschinen", "Kurzhanteln", "Kabelzug", "Körpergewicht",
                                "Kurze, intensive Einheiten", "Supersätze", "Ausdauer ergänzend"]
    static let allergyOptions = ["Gluten", "Laktose", "Nüsse", "Erdnüsse", "Ei", "Soja", "Fisch",
                                 "Krebstiere", "Sellerie", "Senf", "Sesam", "Lupinen"]

    // MARK: Ablauf

    var steps: [Step] {
        var result: [Step] = [.welcome, .goals, .aboutYou, .activity]
        if needsGoalDetails { result.append(.goalDetails) }
        result.append(contentsOf: [.nutrition, .modules, .summary])
        return result
    }

    var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }
    var progress: Double { Double(stepIndex) / Double(max(steps.count - 1, 1)) }

    var needsGoalDetails: Bool {
        goals.contains { $0.needsTargetWeight || $0.needsTrainingDetails || $0 == .adaptedTraining || $0 == .rehabilitation }
    }

    var canContinue: Bool {
        switch step {
        case .goals: !goals.isEmpty
        case .aboutYou: heightCm >= 100 && heightCm <= 250 && weightKg >= 25 && weightKg <= 350
        default: true
        }
    }

    func next() {
        prepareTransition(from: step)
        guard let idx = steps.firstIndex(of: step), idx + 1 < steps.count else { return }
        step = steps[idx + 1]
    }

    func back() {
        guard let idx = steps.firstIndex(of: step), idx > 0 else { return }
        step = steps[idx - 1]
    }

    private func prepareTransition(from step: Step) {
        if step == .goals && !modulesTouched {
            modules = recommendedModules
        }
    }

    // MARK: Ziele

    func toggle(_ goal: FitnessGoal) {
        if let idx = goals.firstIndex(of: goal) {
            goals.remove(at: idx)
            if primaryGoal == goal { primaryGoal = goals.first }
        } else {
            // Widersprüchliche Energieziele schliessen sich aus
            let conflicting: [FitnessGoal] = switch goal {
            case .loseWeight: [.gainWeight]
            case .gainWeight: [.loseWeight]
            default: []
            }
            goals.removeAll { conflicting.contains($0) }
            goals.append(goal)
            if primaryGoal == nil || conflicting.contains(primaryGoal!) { primaryGoal = goal }
        }
    }

    var resolvedPrimaryGoal: FitnessGoal {
        primaryGoal ?? goals.min(by: { $0.priority < $1.priority }) ?? .healthierLife
    }

    func setModule(_ module: AppModule, enabled: Bool) {
        modulesTouched = true
        if enabled { modules.insert(module) } else { modules.remove(module) }
    }

    var recommendedModules: Set<AppModule> {
        var set: Set<AppModule> = [.nutrition, .water]
        if goals.contains(where: { $0.needsTrainingDetails || $0 == .trackOnly }) || experience != .none {
            set.insert(.training)
        }
        if goals.contains(where: { [.loseWeight, .gainWeight, .buildMuscle, .recomposition].contains($0) }) {
            set.insert(.measurements)
        }
        if goals.contains(.buildMuscle) || goals.contains(.strengthEndurance) {
            set.insert(.advancedTrainingStats)
        }
        if goals.contains(.healthierLife) || goals.contains(.fitness) {
            set.insert(.habits)
        }
        return set
    }

    // MARK: Einheiten

    var weightKg: Double { weightUnit.toKg(weightInput) }
    var targetWeightKg: Double? { targetWeightInput.map { weightUnit.toKg($0) } }

    func switchWeightUnit(to unit: WeightUnit) {
        guard unit != weightUnit else { return }
        let kg = weightKg
        let target = targetWeightKg
        weightUnit = unit
        weightInput = (unit.fromKg(kg) * 10).rounded() / 10
        targetWeightInput = target.map { (unit.fromKg($0) * 10).rounded() / 10 }
    }

    var age: Int {
        guard hasBirthDate else { return 30 }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    /// Sinnvolle Bandbreite für das Veränderungstempo.
    var rateRange: ClosedRange<Double> {
        resolvedPrimaryGoal == .gainWeight ? 0.1...0.5 : 0.1...1.0
    }

    var rateDescription: String {
        let percent = weeklyRateKg / max(weightKg, 1) * 100
        if resolvedPrimaryGoal == .gainWeight {
            return weeklyRateKg <= 0.25 ? "Moderat – gut für langfristigen Aufbau" : "Zügig – mehr Fettzunahme wahrscheinlich"
        }
        switch percent {
        case ..<0.5: return "Sanft – gut durchzuhalten"
        case ..<0.8: return "Ausgewogen – empfohlen"
        case ...1.0: return "Ambitioniert – nur kurzfristig sinnvoll"
        default: return "Zu schnell – wird auf 1 % pro Woche begrenzt"
        }
    }

    // MARK: Ergebnis

    var energyInputs: EnergyInputs {
        EnergyInputs(sex: sex, age: age, weightKg: weightKg, heightCm: heightCm, bodyFatPercent: bodyFatPercent,
                     activity: activity, goal: resolvedPrimaryGoal, weeklyRateKg: weeklyRateKg,
                     special: specialSituation, experience: experience)
    }

    var energyResult: EnergyResult { EnergyCalculator.compute(energyInputs) }

    /// Legt Profil, Startgewicht, Zielphase und Einstellungen an.
    func complete(context: ModelContext, preferences: AppPreferences) {
        let result = energyResult
        let profile = UserProfile()
        profile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.birthDate = hasBirthDate ? birthDate : nil
        profile.physiologicalSex = sex
        profile.genderIdentity = genderIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.heightCm = heightCm
        profile.startWeightKg = weightKg
        profile.bodyFatPercent = bodyFatPercent
        profile.activityLevel = activity
        profile.specialSituation = specialSituation
        profile.trainingExperience = experience
        profile.trainingDaysPerWeek = trainingDays
        profile.weeklyWorkoutTarget = trainingDays
        profile.sessionDurationMin = sessionMinutes
        profile.trainingLocation = location
        profile.preferredMethods = Array(preferredMethods).sorted()
        profile.strengths = strengths
        profile.weaknesses = weaknesses
        profile.adaptationsNote = adaptationsNote
        profile.loadLimitsNote = loadLimitsNote
        profile.professionalGuidelines = professionalGuidelines
        profile.excludedExerciseIDs = []
        if !excludedExercises.isEmpty {
            profile.adaptationsNote = [adaptationsNote, "Nicht geeignete Übungen: \(excludedExercises)"]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }
        profile.goals = goals.isEmpty ? [.healthierLife] : goals
        profile.primaryGoal = resolvedPrimaryGoal
        profile.targetWeightKg = targetWeightKg
        profile.weeklyRateKg = weeklyRateKg
        profile.dietType = diet
        profile.allergies = Array(allergies).sorted()
        profile.excludedFoods = Self.splitList(excludedFoods)
        profile.preferredFoods = Self.splitList(preferredFoods)
        profile.mealsPerDay = mealsPerDay
        profile.wantsRecipes = wantsRecipes
        profile.wantsCalorieTarget = wantsCalorieTarget
        ProfileService.apply(result, to: profile)
        context.insert(profile)

        let weight = WeightEntry(kg: weightKg, date: .now, source: .manual, note: "Startgewicht")
        context.insert(weight)

        let phase = GoalPhase(goals: profile.goals, primary: profile.primaryGoal, calorieTarget: result.calorieTarget,
                              proteinTargetG: result.proteinG, startWeightKg: weightKg, targetWeightKg: targetWeightKg)
        context.insert(phase)

        AuditLog.record(context, actor: .user, summary: "Profil erstellt",
                        detail: "Ziele: \(profile.goals.map(\.title).joined(separator: ", "))", entityType: EntityType.profile)
        context.saveQuietly()

        preferences.weightUnit = weightUnit
        preferences.energyUnit = energyUnit
        preferences.enabledModules = modules
        preferences.dashboardCards = DashboardCardKind.defaults(for: profile.primaryGoal)
        preferences.isGuestMode = isGuest
        preferences.appleUserID = appleUserID
        preferences.hasSeenTutorial = false
        preferences.hasCompletedOnboarding = true
    }

    private static func splitList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
