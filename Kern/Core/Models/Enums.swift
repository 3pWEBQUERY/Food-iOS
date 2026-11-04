import Foundation
import SwiftUI

// MARK: - Profil

/// Für Energie-Berechnungen relevante physiologische Angabe. Wird bewusst getrennt
/// von der freiwilligen Geschlechtsidentität im Profil behandelt.
enum PhysiologicalSex: String, Codable, CaseIterable, Identifiable {
    case female, male, unspecified
    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: "Weiblich"
        case .male: "Männlich"
        case .unspecified: "Keine Angabe"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: "Überwiegend sitzend"
        case .light: "Leicht aktiv"
        case .moderate: "Mässig aktiv"
        case .active: "Sehr aktiv"
        case .veryActive: "Extrem aktiv"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Bürojob, wenig Bewegung im Alltag"
        case .light: "Viel zu Fuss, 1–2 Trainings pro Woche"
        case .moderate: "Aktiver Alltag, 3–4 Trainings pro Woche"
        case .active: "Körperliche Arbeit oder 5–6 Trainings"
        case .veryActive: "Leistungssport oder harte körperliche Arbeit"
        }
    }

    /// Physical Activity Level (PAL) nach gängigen Referenzwerten.
    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

enum TrainingExperience: String, Codable, CaseIterable, Identifiable {
    case none, beginner, intermediate, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Keine"
        case .beginner: "Einsteiger"
        case .intermediate: "Fortgeschritten"
        case .advanced: "Erfahren"
        }
    }

    var detail: String {
        switch self {
        case .none: "Noch nie regelmässig trainiert"
        case .beginner: "Weniger als 1 Jahr regelmässig"
        case .intermediate: "1–3 Jahre regelmässig"
        case .advanced: "Mehr als 3 Jahre strukturiert"
        }
    }
}

enum TrainingLocation: String, Codable, CaseIterable, Identifiable {
    case gym, home, outdoor, mixed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gym: "Fitnessstudio"
        case .home: "Zuhause"
        case .outdoor: "Draussen"
        case .mixed: "Gemischt"
        }
    }

    var symbol: String {
        switch self {
        case .gym: "dumbbell"
        case .home: "house"
        case .outdoor: "tree"
        case .mixed: "square.grid.2x2"
        }
    }
}

enum SpecialSituation: String, Codable, CaseIterable, Identifiable {
    case none, pregnant, breastfeeding, medicalSupervision
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Keine"
        case .pregnant: "Schwangerschaft"
        case .breastfeeding: "Stillzeit"
        case .medicalSupervision: "Medizinische Begleitung"
        }
    }
}

enum DietType: String, Codable, CaseIterable, Identifiable {
    case omnivore, flexitarian, pescatarian, vegetarian, vegan, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .omnivore: "Mischkost"
        case .flexitarian: "Flexitarisch"
        case .pescatarian: "Pescetarisch"
        case .vegetarian: "Vegetarisch"
        case .vegan: "Vegan"
        case .other: "Andere"
        }
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var symbol: String { rawValue }
    var title: String { self == .kg ? "Kilogramm (kg)" : "Pfund (lb)" }

    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * 2.204_622_62 }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value / 2.204_622_62 }
}

enum EnergyUnit: String, Codable, CaseIterable, Identifiable {
    case kcal, kJ
    var id: String { rawValue }
    var symbol: String { rawValue }
    var title: String { self == .kcal ? "Kilokalorien (kcal)" : "Kilojoule (kJ)" }
}

// MARK: - Ziele

enum EnergyStrategy {
    case deficit, slightDeficit, maintenance, leanSurplus, surplus
}

enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case loseWeight, gainWeight, buildMuscle, recomposition, maintain, fitness,
         strengthEndurance, healthierLife, trackOnly, adaptedTraining, rehabilitation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .loseWeight: "Abnehmen"
        case .gainWeight: "Zunehmen"
        case .buildMuscle: "Muskelaufbau"
        case .recomposition: "Körperrekomposition"
        case .maintain: "Gewicht halten"
        case .fitness: "Fitter werden"
        case .strengthEndurance: "Kraft & Ausdauer"
        case .healthierLife: "Gesünder leben"
        case .trackOnly: "Nur dokumentieren"
        case .adaptedTraining: "Angepasstes Training"
        case .rehabilitation: "Rehabilitation"
        }
    }

    var subtitle: String {
        switch self {
        case .loseWeight: "Körperfett reduzieren"
        case .gainWeight: "Gesund an Gewicht zulegen"
        case .buildMuscle: "Muskulatur gezielt aufbauen"
        case .recomposition: "Fett reduzieren, Muskeln aufbauen"
        case .maintain: "Aktuelles Gewicht stabil halten"
        case .fitness: "Allgemeine Fitness verbessern"
        case .strengthEndurance: "Leistung steigern"
        case .healthierLife: "Bessere Gewohnheiten aufbauen"
        case .trackOnly: "Training und Ernährung festhalten"
        case .adaptedTraining: "Bei individuellen Einschränkungen"
        case .rehabilitation: "Nur mit fachlicher Begleitung"
        }
    }

    var symbol: String {
        switch self {
        case .loseWeight: "arrow.down.right"
        case .gainWeight: "arrow.up.right"
        case .buildMuscle: "dumbbell"
        case .recomposition: "arrow.left.arrow.right"
        case .maintain: "equal"
        case .fitness: "figure.run"
        case .strengthEndurance: "bolt"
        case .healthierLife: "leaf"
        case .trackOnly: "list.bullet.clipboard"
        case .adaptedTraining: "slider.horizontal.3"
        case .rehabilitation: "cross.case"
        }
    }

    var energyStrategy: EnergyStrategy {
        switch self {
        case .loseWeight: .deficit
        case .recomposition: .slightDeficit
        case .gainWeight: .surplus
        case .buildMuscle: .leanSurplus
        default: .maintenance
        }
    }

    /// Ob dieses Ziel ein Wunschgewicht benötigt.
    var needsTargetWeight: Bool { self == .loseWeight || self == .gainWeight }

    /// Ob dieses Ziel Trainingsangaben benötigt.
    var needsTrainingDetails: Bool {
        [.buildMuscle, .recomposition, .strengthEndurance, .fitness, .adaptedTraining, .gainWeight].contains(self)
    }

    /// Protein in g pro kg Referenzgewicht.
    var proteinPerKg: Double {
        switch self {
        case .loseWeight, .recomposition: 2.0
        case .buildMuscle, .strengthEndurance: 1.8
        case .gainWeight, .maintain: 1.6
        case .fitness, .trackOnly, .adaptedTraining, .rehabilitation: 1.4
        case .healthierLife: 1.2
        }
    }

    /// Vorgeschlagene Priorität bei mehreren Zielen (kleiner = wichtiger).
    var priority: Int {
        switch self {
        case .loseWeight: 0
        case .recomposition: 1
        case .buildMuscle: 2
        case .gainWeight: 3
        case .maintain: 4
        case .strengthEndurance: 5
        case .fitness: 6
        case .adaptedTraining: 7
        case .rehabilitation: 8
        case .healthierLife: 9
        case .trackOnly: 10
        }
    }
}

enum EnergyFormula: String, Codable, CaseIterable, Identifiable {
    case automatic, mifflinStJeor, muellerBMI, muellerFFM, katchMcArdle
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatisch"
        case .mifflinStJeor: "Mifflin-St.-Jeor"
        case .muellerBMI: "Müller (Gewicht)"
        case .muellerFFM: "Müller (Körperzusammensetzung)"
        case .katchMcArdle: "Katch-McArdle"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Wählt anhand deiner Angaben die passende Formel."
        case .mifflinStJeor: "Standardformel aus Gewicht, Grösse, Alter und physiologischer Angabe."
        case .muellerBMI: "Formel nach Müller et al. (2004), entwickelt an einer deutschen Stichprobe."
        case .muellerFFM: "Müller-Formel mit fettfreier Masse – nur mit Körperfettanteil."
        case .katchMcArdle: "Basiert ausschliesslich auf der fettfreien Masse."
        }
    }

    var needsBodyFat: Bool { self == .muellerFFM || self == .katchMcArdle }
}

// MARK: - Ernährung

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittagessen"
        case .dinner: "Abendessen"
        case .snack: "Snacks"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "carrot"
        }
    }

    /// Passende Mahlzeit anhand der Uhrzeit.
    static func suggested(for date: Date = .now) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<10: return .breakfast
        case 10..<11: return .snack
        case 11..<14: return .lunch
        case 14..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

/// Nachvollziehbarer Qualitätsstatus eines Produktdatensatzes.
enum DataQuality: String, Codable, CaseIterable, Identifiable {
    case verified, manufacturer, reference, community, aiUnconfirmed, incomplete
    var id: String { rawValue }

    var title: String {
        switch self {
        case .verified: "Verifiziert"
        case .manufacturer: "Herstellerangaben"
        case .reference: "Referenzwert"
        case .community: "Community-Eintrag"
        case .aiUnconfirmed: "KI-erkannt · unbestätigt"
        case .incomplete: "Unvollständig"
        }
    }

    var symbol: String {
        switch self {
        case .verified: "checkmark.seal"
        case .manufacturer: "building.2"
        case .reference: "book.closed"
        case .community: "person.2"
        case .aiUnconfirmed: "sparkles"
        case .incomplete: "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .verified: Theme.positive
        case .manufacturer, .reference: Theme.protein
        case .community: .secondary
        case .aiUnconfirmed, .incomplete: Theme.warning
        }
    }
}

enum FoodSource: String, Codable, CaseIterable, Identifiable {
    case reference, kernCatalog, openFoodFacts, manufacturer, user, ai
    var id: String { rawValue }

    var title: String {
        switch self {
        case .reference: "Kern Basisdaten"
        case .kernCatalog: "Kern Katalog"
        case .openFoodFacts: "Open Food Facts"
        case .manufacturer: "Hersteller"
        case .user: "Eigener Eintrag"
        case .ai: "KI-Schätzung"
        }
    }

    /// Lizenzhinweis, falls nötig (Open Food Facts: ODbL).
    var licenseNote: String? {
        switch self {
        case .openFoodFacts: "Daten von Open Food Facts, lizenziert unter der Open Database License (ODbL)."
        default: nil
        }
    }
}

enum EntrySource: String, Codable, CaseIterable {
    case manual, search, barcode, photo, voice, coach, recipe, savedMeal, copy, health, quickAdd, widget

    var title: String {
        switch self {
        case .manual: "Manuell"
        case .search: "Suche"
        case .barcode: "Barcode"
        case .photo: "Foto"
        case .voice: "Sprache"
        case .coach: "Coach"
        case .recipe: "Rezept"
        case .savedMeal: "Gespeicherte Mahlzeit"
        case .copy: "Kopiert"
        case .health: "Apple Health"
        case .quickAdd: "Schnelleintrag"
        case .widget: "Widget"
        }
    }
}

// MARK: - Training

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms, abs, quads, hamstrings, glutes, calves, fullBody, cardio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "Brust"
        case .back: "Rücken"
        case .shoulders: "Schultern"
        case .biceps: "Bizeps"
        case .triceps: "Trizeps"
        case .forearms: "Unterarme"
        case .abs: "Rumpf"
        case .quads: "Quadrizeps"
        case .hamstrings: "Beinbeuger"
        case .glutes: "Gesäss"
        case .calves: "Waden"
        case .fullBody: "Ganzkörper"
        case .cardio: "Ausdauer"
        }
    }
}

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case compound, isolation, cardio, mobility, core
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compound: "Grundübung"
        case .isolation: "Isolation"
        case .cardio: "Ausdauer"
        case .mobility: "Mobilität"
        case .core: "Rumpf"
        }
    }
}

enum EquipmentKind: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, smith, kettlebell, band, bodyweight, cardioMachine, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .barbell: "Langhantel"
        case .dumbbell: "Kurzhantel"
        case .machine: "Maschine"
        case .cable: "Kabelzug"
        case .smith: "Multipresse"
        case .kettlebell: "Kettlebell"
        case .band: "Widerstandsband"
        case .bodyweight: "Körpergewicht"
        case .cardioMachine: "Cardiogerät"
        case .other: "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .barbell: "figure.strengthtraining.traditional"
        case .dumbbell: "dumbbell"
        case .machine: "gearshape.2"
        case .cable: "cable.connector"
        case .smith: "square.split.1x2"
        case .kettlebell: "scalemass"
        case .band: "lasso"
        case .bodyweight: "figure.core.training"
        case .cardioMachine: "figure.indoor.cycle"
        case .other: "ellipsis.circle"
        }
    }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "Einsteiger"
        case .intermediate: "Mittel"
        case .advanced: "Fortgeschritten"
        }
    }
}

enum TrainingFocus: String, Codable, CaseIterable, Identifiable {
    case strength, hypertrophy, endurance, mobility
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Maximalkraft"
        case .hypertrophy: "Muskelaufbau"
        case .endurance: "Kraftausdauer"
        case .mobility: "Mobilität"
        }
    }
}

enum SetKind: String, Codable, CaseIterable, Identifiable {
    case warmup, working, drop, failure
    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup: "Aufwärmsatz"
        case .working: "Arbeitssatz"
        case .drop: "Dropsatz"
        case .failure: "Bis Muskelversagen"
        }
    }

    var shortLabel: String {
        switch self {
        case .warmup: "W"
        case .working: ""
        case .drop: "D"
        case .failure: "F"
        }
    }
}

// MARK: - Module & Dashboard

/// Zuschaltbare App-Module (unabhängig von den Zielen).
enum AppModule: String, Codable, CaseIterable, Identifiable {
    case nutrition, water, training, supplements, cycle, measurements, progressPhotos, bodyAvatar, advancedTrainingStats, habits
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nutrition: "Ernährungstracking"
        case .water: "Wassertracking"
        case .training: "Gym-Tagebuch"
        case .supplements: "Supplements"
        case .cycle: "Zyklustracking"
        case .measurements: "Körpermasse"
        case .progressPhotos: "Fortschrittsfotos"
        case .bodyAvatar: "3D-Körper"
        case .advancedTrainingStats: "Erweiterte Trainingsstatistiken"
        case .habits: "Gewohnheiten"
        }
    }

    var detail: String {
        switch self {
        case .nutrition: "Mahlzeiten, Kalorien und Makros erfassen"
        case .water: "Trinkziel und Getränke"
        case .training: "Trainingspläne, Sätze und Rekorde"
        case .supplements: "Routinen, Einnahmen und Vorrat"
        case .cycle: "Kalender, Symptome und Wohlbefinden"
        case .measurements: "Umfänge und Körperfett"
        case .progressPhotos: "Private Vergleichsfotos"
        case .bodyAvatar: "Illustrative Körperdarstellung"
        case .advancedTrainingStats: "Volumen, Muskelgruppen, e1RM"
        case .habits: "Eigene tägliche Gewohnheiten"
        }
    }

    var symbol: String {
        switch self {
        case .nutrition: "fork.knife"
        case .water: "drop"
        case .training: "dumbbell"
        case .supplements: "pills"
        case .cycle: "circle.dashed"
        case .measurements: "ruler"
        case .progressPhotos: "photo.on.rectangle"
        case .bodyAvatar: "figure.stand"
        case .advancedTrainingStats: "chart.bar.xaxis"
        case .habits: "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .nutrition: Theme.accent
        case .water: Theme.water
        case .training, .advancedTrainingStats: Theme.training
        case .supplements: Theme.supplement
        case .cycle: Theme.cycle
        case .measurements, .bodyAvatar, .progressPhotos: Theme.weight
        case .habits: Theme.positive
        }
    }

    /// Sensible Module, die besonders geschützt werden.
    var isSensitive: Bool { self == .cycle || self == .progressPhotos }
}

enum DashboardCardKind: String, Codable, CaseIterable, Identifiable {
    case calorieBudget, macros, water, weightTrend, nextWorkout, trainingWeek, strength,
         activity, supplements, habits, cycle, weeklyInsight, consistency, measurements
    var id: String { rawValue }

    var title: String {
        switch self {
        case .calorieBudget: "Kalorienbudget"
        case .macros: "Makronährstoffe"
        case .water: "Wasser"
        case .weightTrend: "Gewichtstrend"
        case .nextWorkout: "Nächstes Training"
        case .trainingWeek: "Trainingswoche"
        case .strength: "Kraftentwicklung"
        case .activity: "Aktivität"
        case .supplements: "Supplements heute"
        case .habits: "Gewohnheiten"
        case .cycle: "Zyklus"
        case .weeklyInsight: "Wochenanalyse"
        case .consistency: "Konstanz"
        case .measurements: "Körpermasse"
        }
    }

    var symbol: String {
        switch self {
        case .calorieBudget: "flame"
        case .macros: "chart.bar"
        case .water: "drop"
        case .weightTrend: "scalemass"
        case .nextWorkout: "dumbbell"
        case .trainingWeek: "calendar"
        case .strength: "chart.line.uptrend.xyaxis"
        case .activity: "figure.walk"
        case .supplements: "pills"
        case .habits: "checkmark.circle"
        case .cycle: "circle.dashed"
        case .weeklyInsight: "text.magnifyingglass"
        case .consistency: "square.grid.3x3.fill"
        case .measurements: "ruler"
        }
    }

    /// Modul, das für diese Karte aktiv sein muss (nil = immer verfügbar).
    var requiredModule: AppModule? {
        switch self {
        case .calorieBudget, .macros, .consistency: .nutrition
        case .water: .water
        case .nextWorkout, .trainingWeek: .training
        case .strength: .training
        case .supplements: .supplements
        case .habits: .habits
        case .cycle: .cycle
        case .measurements: .measurements
        case .weightTrend, .activity, .weeklyInsight: nil
        }
    }

    /// Zielabhängige Standardanordnung (Abschnitt 3.1 der Produktvorgaben).
    static func defaults(for goal: FitnessGoal) -> [DashboardCardKind] {
        switch goal {
        case .loseWeight:
            [.calorieBudget, .macros, .weightTrend, .activity, .water, .nextWorkout, .weeklyInsight]
        case .buildMuscle, .gainWeight, .recomposition, .strengthEndurance:
            [.nextWorkout, .calorieBudget, .macros, .strength, .trainingWeek, .weightTrend, .weeklyInsight]
        case .maintain:
            [.weightTrend, .consistency, .calorieBudget, .activity, .habits, .weeklyInsight]
        case .fitness, .healthierLife:
            [.activity, .nextWorkout, .trainingWeek, .water, .habits, .calorieBudget, .weeklyInsight]
        case .trackOnly:
            [.calorieBudget, .macros, .trainingWeek, .weightTrend, .water, .weeklyInsight]
        case .adaptedTraining, .rehabilitation:
            [.nextWorkout, .activity, .trainingWeek, .habits, .water, .weeklyInsight]
        }
    }
}

/// Bereiche der Einstellungen (auch für Coach-Navigation).
enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Codable {
    case profile, goals, targets, modules, dashboard, units, health, notifications, coach, privacy, auditLog, tutorial, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profil & Körperdaten"
        case .goals: "Ziele"
        case .targets: "Kalorien- & Makroziele"
        case .modules: "Module"
        case .dashboard: "Startseite anpassen"
        case .units: "Masseinheiten"
        case .health: "Apple Health"
        case .notifications: "Erinnerungen"
        case .coach: "KI-Coach"
        case .privacy: "Datenschutz & Daten"
        case .auditLog: "Änderungsprotokoll"
        case .tutorial: "Einführung & Hilfe"
        case .about: "Über Kern"
        }
    }

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .goals: "target"
        case .targets: "flame"
        case .modules: "square.grid.2x2"
        case .dashboard: "rectangle.3.group"
        case .units: "ruler"
        case .health: "heart"
        case .notifications: "bell"
        case .coach: "bubble.left.and.text.bubble.right"
        case .privacy: "lock.shield"
        case .auditLog: "clock.arrow.circlepath"
        case .tutorial: "questionmark.circle"
        case .about: "info.circle"
        }
    }

    /// Suchbegriffe, damit der Coach Einstellungen finden kann.
    var keywords: [String] {
        switch self {
        case .profile: ["profil", "grösse", "körpergrösse", "alter", "geburtsdatum", "körperfett", "name"]
        case .goals: ["ziel", "ziele", "abnehmen", "zunehmen", "muskelaufbau", "wunschgewicht"]
        case .targets: ["kalorien", "makro", "protein", "kohlenhydrate", "fett", "kalorienziel", "formel", "tdee", "grundumsatz"]
        case .modules: ["modul", "module", "zyklus aktivieren", "supplements aktivieren", "funktionen"]
        case .dashboard: ["startseite", "dashboard", "karten", "anordnen"]
        case .units: ["einheit", "einheiten", "kilogramm", "pfund", "kilojoule", "masseinheiten"]
        case .health: ["health", "apple health", "healthkit", "schritte", "synchron"]
        case .notifications: ["erinnerung", "erinnerungen", "benachrichtigung", "mitteilung"]
        case .coach: ["coach", "ki", "automatisierung", "assistent"]
        case .privacy: ["datenschutz", "export", "löschen", "daten", "zustimmung", "privat"]
        case .auditLog: ["protokoll", "verlauf", "änderungen", "rückgängig"]
        case .tutorial: ["tutorial", "einführung", "hilfe", "anleitung"]
        case .about: ["über", "version", "lizenz", "quellen"]
        }
    }
}
