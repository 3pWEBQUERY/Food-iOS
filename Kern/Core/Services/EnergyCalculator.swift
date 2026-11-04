import Foundation

/// Eingaben für die Energiebedarfsberechnung.
struct EnergyInputs: Hashable {
    var sex: PhysiologicalSex
    var age: Int
    var weightKg: Double
    var heightCm: Double
    var bodyFatPercent: Double?
    var activity: ActivityLevel
    var goal: FitnessGoal
    var weeklyRateKg: Double
    var special: SpecialSituation
    var experience: TrainingExperience = .beginner

    init(sex: PhysiologicalSex, age: Int, weightKg: Double, heightCm: Double, bodyFatPercent: Double?,
         activity: ActivityLevel, goal: FitnessGoal, weeklyRateKg: Double, special: SpecialSituation,
         experience: TrainingExperience = .beginner) {
        self.sex = sex
        self.age = age
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.bodyFatPercent = bodyFatPercent
        self.activity = activity
        self.goal = goal
        self.weeklyRateKg = weeklyRateKg
        self.special = special
        self.experience = experience
    }

    init(profile: UserProfile, currentWeightKg: Double?) {
        self.init(sex: profile.physiologicalSex, age: profile.age,
                  weightKg: currentWeightKg ?? profile.startWeightKg, heightCm: profile.heightCm,
                  bodyFatPercent: profile.bodyFatPercent, activity: profile.activityLevel,
                  goal: profile.primaryGoal, weeklyRateKg: profile.weeklyRateKg,
                  special: profile.specialSituation, experience: profile.trainingExperience)
    }

    var bmi: Double {
        let h = heightCm / 100
        return h > 0 ? weightKg / (h * h) : 0
    }

    var fatFreeMassKg: Double? {
        guard let bf = bodyFatPercent, (3...70).contains(bf) else { return nil }
        return weightKg * (1 - bf / 100)
    }
}

struct SafetyNote: Identifiable, Hashable {
    enum Severity: Hashable { case info, warning }
    var id = UUID()
    var severity: Severity
    var text: String
}

struct EnergyResult: Hashable {
    var formula: EnergyFormula
    var bmr: Double
    var activityFactor: Double
    var tdee: Double
    var adjustmentKcal: Double
    var calorieTarget: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int
    var waterMl: Int
    var notes: [SafetyNote]

    /// Verständliche Herleitung, Schritt für Schritt.
    var explanation: [String]
}

/// Schätzt den Energiebedarf mit etablierten, nachvollziehbaren Formeln.
/// Die KI erklärt diese Werte nur – sie berechnet sie nicht selbst.
enum EnergyCalculator {
    static let kcalPerKgBodyMass = 7700.0
    static let kcalPerMJ = 239.006

    // MARK: Formeln für den Grundumsatz (kcal/Tag)

    /// Mifflin-St.-Jeor (1990).
    static func mifflinStJeor(_ i: EnergyInputs) -> Double {
        let base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * Double(i.age)
        switch i.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    /// Müller et al. (2004), Variante mit Körpergewicht.
    /// REE [MJ/d] = 0.047 · Gewicht + 1.009 · S − 0.01452 · Alter + 3.21
    static func muellerBMI(_ i: EnergyInputs) -> Double {
        let mj = 0.047 * i.weightKg + 1.009 * sexFactor(i.sex) - 0.01452 * Double(i.age) + 3.21
        return mj * kcalPerMJ
    }

    /// Müller et al. (2004), Variante mit Körperzusammensetzung.
    /// REE [MJ/d] = 0.05192 · FFM + 0.04036 · FM + 0.869 · S − 0.01181 · Alter + 2.992
    static func muellerFFM(_ i: EnergyInputs) -> Double? {
        guard let ffm = i.fatFreeMassKg else { return nil }
        let fm = i.weightKg - ffm
        let mj = 0.05192 * ffm + 0.04036 * fm + 0.869 * sexFactor(i.sex) - 0.01181 * Double(i.age) + 2.992
        return mj * kcalPerMJ
    }

    /// Katch-McArdle: 370 + 21.6 · FFM.
    static func katchMcArdle(_ i: EnergyInputs) -> Double? {
        guard let ffm = i.fatFreeMassKg else { return nil }
        return 370 + 21.6 * ffm
    }

    private static func sexFactor(_ sex: PhysiologicalSex) -> Double {
        switch sex {
        case .male: 1
        case .female: 0
        case .unspecified: 0.5
        }
    }

    /// Nachvollziehbare Auswahlregel: Mit Körperfettanteil wird die Müller-Formel mit
    /// Körperzusammensetzung verwendet, sonst Mifflin-St.-Jeor.
    static func resolve(_ requested: EnergyFormula, for i: EnergyInputs) -> EnergyFormula {
        switch requested {
        case .automatic:
            return i.fatFreeMassKg != nil ? .muellerFFM : .mifflinStJeor
        case .muellerFFM, .katchMcArdle:
            return i.fatFreeMassKg != nil ? requested : .mifflinStJeor
        default:
            return requested
        }
    }

    static func bmr(_ i: EnergyInputs, formula: EnergyFormula) -> (EnergyFormula, Double) {
        let resolved = resolve(formula, for: i)
        let value: Double
        switch resolved {
        case .mifflinStJeor, .automatic: value = mifflinStJeor(i)
        case .muellerBMI: value = muellerBMI(i)
        case .muellerFFM: value = muellerFFM(i) ?? mifflinStJeor(i)
        case .katchMcArdle: value = katchMcArdle(i) ?? mifflinStJeor(i)
        }
        return (resolved, value)
    }

    // MARK: Gesamtberechnung

    /// Berechnet Bedarf und Zielwerte inklusive Sicherheitsregeln.
    /// - Parameter tdeeOverride: adaptive Schätzung des Gesamtbedarfs, falls akzeptiert.
    static func compute(_ i: EnergyInputs, formula: EnergyFormula = .automatic, tdeeOverride: Double? = nil) -> EnergyResult {
        var notes: [SafetyNote] = []
        var steps: [String] = []

        let (resolved, bmr) = EnergyCalculator.bmr(i, formula: formula)
        let factor = i.activity.factor
        let formulaTDEE = bmr * factor
        let tdee = tdeeOverride ?? formulaTDEE

        steps.append("Grundumsatz nach \(resolved.title): \(Fmt.number(bmr)) kcal")
        if let tdeeOverride {
            steps.append("Gesamtbedarf aus deinen Verlaufsdaten geschätzt: \(Fmt.number(tdeeOverride)) kcal (Formel: \(Fmt.number(formulaTDEE)) kcal)")
        } else {
            steps.append("× Aktivitätsfaktor \(Fmt.decimal(factor, maxDigits: 3)) (\(i.activity.title)) = \(Fmt.number(tdee)) kcal Gesamtbedarf")
        }

        if i.sex == .unspecified {
            notes.append(SafetyNote(severity: .info, text: "Ohne physiologische Angabe wird ein Mittelwert verwendet. Die Schätzung ist dadurch ungenauer."))
        }

        // Ziel-Anpassung
        var adjustment: Double = 0
        switch i.goal.energyStrategy {
        case .deficit:
            let rate = i.weeklyRateKg.clamped(0.1...1.0)
            let maxRate = i.weightKg * 0.01
            let effectiveRate = min(rate, maxRate)
            if rate > maxRate {
                notes.append(SafetyNote(severity: .warning, text: "Das Tempo wurde auf höchstens 1 % des Körpergewichts pro Woche begrenzt (\(Fmt.decimal(maxRate, maxDigits: 2)) kg)."))
            }
            adjustment = -(effectiveRate * kcalPerKgBodyMass / 7)
            let maxDeficit = tdee * 0.25
            if -adjustment > maxDeficit {
                adjustment = -maxDeficit
                notes.append(SafetyNote(severity: .warning, text: "Das Defizit wurde auf 25 % des Gesamtbedarfs begrenzt."))
            }
        case .slightDeficit:
            adjustment = -min(tdee * 0.10, 300)
        case .leanSurplus:
            switch i.experience {
            case .none, .beginner: adjustment = min(tdee * 0.12, 350)
            case .intermediate: adjustment = min(tdee * 0.08, 250)
            case .advanced: adjustment = min(tdee * 0.05, 180)
            }
        case .surplus:
            let rate = i.weeklyRateKg.clamped(0.1...0.5)
            adjustment = min(rate * kcalPerKgBodyMass / 7, 500)
        case .maintenance:
            adjustment = 0
        }

        // Sicherheitsregeln für besondere Situationen
        if adjustment < 0 {
            if i.special == .pregnant || i.special == .breastfeeding {
                adjustment = 0
                notes.append(SafetyNote(severity: .warning, text: "Während \(i.special == .pregnant ? "der Schwangerschaft" : "der Stillzeit") berechnet Kern kein Kaloriendefizit. Bitte stimme Ernährungsziele mit deiner Ärztin, deinem Arzt oder deiner Hebamme ab."))
            } else if i.age < 18 {
                adjustment = 0
                notes.append(SafetyNote(severity: .warning, text: "Für Personen unter 18 Jahren wird kein Kaloriendefizit berechnet."))
            } else if i.bmi > 0 && i.bmi < 18.5 {
                adjustment = 0
                notes.append(SafetyNote(severity: .warning, text: "Dein BMI liegt unter 18.5. Ein Kaloriendefizit wird nicht empfohlen – bitte lass dich fachlich beraten."))
            }
        }
        if i.special == .medicalSupervision {
            notes.append(SafetyNote(severity: .info, text: "Du hast eine medizinische Begleitung angegeben. Fachliche Vorgaben haben Vorrang vor diesen Schätzungen."))
        }

        var target = tdee + adjustment

        // Untergrenze: nie unter Grundumsatz bzw. allgemeine Mindestwerte
        let absoluteFloor: Double = switch i.sex {
        case .male: 1500
        case .female: 1200
        case .unspecified: 1350
        }
        let floor = max(bmr, absoluteFloor)
        if target < floor {
            target = floor
            notes.append(SafetyNote(severity: .warning, text: "Das Ziel wurde auf \(Fmt.number(floor)) kcal angehoben, damit es nicht unter deinem Grundumsatz bzw. einem sicheren Mindestwert liegt."))
        }
        if i.special == .breastfeeding {
            notes.append(SafetyNote(severity: .info, text: "In der Stillzeit ist der Energiebedarf erhöht. Dieser Mehrbedarf ist individuell und in der Schätzung nicht enthalten."))
        }

        target = target.rounded(toNearest: 10)
        adjustment = target - tdee

        if adjustment < -1 {
            steps.append("Defizit für dein Ziel: \(Fmt.number(-adjustment)) kcal ≈ \(Fmt.decimal(-adjustment * 7 / kcalPerKgBodyMass, maxDigits: 2)) kg pro Woche")
        } else if adjustment > 1 {
            steps.append("Überschuss für dein Ziel: \(Fmt.number(adjustment)) kcal")
        } else {
            steps.append("Kein Defizit oder Überschuss – Ziel: Gewicht halten")
        }
        steps.append("Tagesziel: \(Fmt.number(target)) kcal")

        // Makros
        let h = i.heightCm / 100
        let referenceWeight: Double = {
            guard i.bmi > 30 else { return i.weightKg }
            let ideal = 25 * h * h
            return ideal + 0.25 * (i.weightKg - ideal)
        }()
        var proteinPerKg = i.goal.proteinPerKg
        if i.special == .pregnant || i.special == .breastfeeding { proteinPerKg = max(proteinPerKg, 1.2) }
        let protein = (referenceWeight * proteinPerKg).rounded()
        let fat = max(target * 0.28 / 9, i.weightKg * 0.6).rounded()
        var carbs = ((target - protein * 4 - fat * 9) / 4).rounded()
        if carbs < 50 {
            carbs = 50
            notes.append(SafetyNote(severity: .info, text: "Kohlenhydrate wurden auf mindestens 50 g gesetzt. Die Summe der Makros kann daher leicht vom Kalorienziel abweichen."))
        }
        let fiber = max((target / 1000 * 14).rounded(), 25)
        steps.append("Protein: \(Fmt.decimal(proteinPerKg)) g pro kg \(i.bmi > 30 ? "angepasstem " : "")Körpergewicht = \(Fmt.number(protein)) g")
        steps.append("Fett: ca. 28 % der Energie = \(Fmt.number(fat)) g · Kohlenhydrate: Rest = \(Fmt.number(carbs)) g")

        var water = (i.weightKg * 35).rounded(toNearest: 100)
        if i.special == .pregnant { water += 300 }
        if i.special == .breastfeeding { water += 700 }
        water = water.clamped(1500...4500)

        return EnergyResult(formula: resolved, bmr: bmr.rounded(), activityFactor: factor, tdee: tdee.rounded(),
                            adjustmentKcal: adjustment.rounded(), calorieTarget: Int(target),
                            proteinG: Int(protein), carbsG: Int(carbs), fatG: Int(fat), fiberG: Int(fiber),
                            waterMl: Int(water), notes: notes, explanation: steps)
    }

    /// Prüft manuell eingegebene Zielwerte und liefert Hinweise.
    static func validateManualTarget(kcal: Int, inputs: EnergyInputs) -> [SafetyNote] {
        var notes: [SafetyNote] = []
        let (_, bmr) = EnergyCalculator.bmr(inputs, formula: .automatic)
        if Double(kcal) < bmr {
            notes.append(SafetyNote(severity: .warning, text: "Dein Ziel liegt unter dem geschätzten Grundumsatz (\(Fmt.number(bmr)) kcal). Das wird ohne fachliche Begleitung nicht empfohlen."))
        }
        if kcal < 1200 {
            notes.append(SafetyNote(severity: .warning, text: "Ziele unter 1’200 kcal sind ohne medizinische Begleitung nicht geeignet."))
        }
        if (inputs.special == .pregnant || inputs.special == .breastfeeding) && Double(kcal) < bmr * inputs.activity.factor {
            notes.append(SafetyNote(severity: .warning, text: "In Schwangerschaft und Stillzeit sollte kein Defizit ohne ärztliche Begleitung geplant werden."))
        }
        return notes
    }

    /// Kleinstes erlaubtes manuelles Ziel.
    static func minimumAllowedTarget(for inputs: EnergyInputs) -> Int { 1000 }
}
