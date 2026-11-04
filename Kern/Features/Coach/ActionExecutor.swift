import Foundation
import SwiftData

/// Prüft Aktionen auf Wertebereiche, Vollständigkeit und Berechtigungen.
@MainActor
enum ActionValidator {
    /// Gibt eine verständliche Fehlermeldung zurück oder `nil`, wenn die Aktion gültig ist.
    static func validate(_ action: CoachAction, prefs: AppPreferences, context: ModelContext) -> String? {
        let p = action.params
        switch action.kind {
        case .logWeight:
            guard let kg = CoachParam.double(p[CoachParam.kg]) else { return "Es fehlt ein Gewichtswert." }
            guard (25...350).contains(kg) else { return "Gewicht ausserhalb des plausiblen Bereichs (25–350 kg)." }
        case .logWater:
            guard let ml = CoachParam.double(p[CoachParam.ml]) else { return "Es fehlt eine Trinkmenge." }
            guard (10...5000).contains(ml) else { return "Trinkmenge ausserhalb des plausiblen Bereichs (10–5000 ml)." }
        case .logFood:
            guard let grams = CoachParam.double(p[CoachParam.grams]) else { return "Es fehlt eine Menge." }
            guard (1...3000).contains(grams) else { return "Menge ausserhalb des plausiblen Bereichs (1–3000 g)." }
            if p[CoachParam.foodID] == nil {
                guard (p[CoachParam.name] ?? "").isEmpty == false else { return "Es fehlt ein Lebensmittel." }
                guard let kcal = CoachParam.double(p[CoachParam.kcal100]) else { return "Es fehlen Nährwerte." }
                let total = kcal * grams / 100
                guard (0...5000).contains(total) else { return "Energie ausserhalb des plausiblen Bereichs (0–5000 kcal)." }
            } else if let id = UUID(uuidString: p[CoachParam.foodID] ?? "") {
                let found = (try? context.fetchCount(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id }))) ?? 0
                if found == 0 { return "Das Lebensmittel wurde nicht gefunden." }
            }
        case .addWorkoutNote:
            guard p[CoachParam.sessionID] != nil else { return "Bitte wähle die Trainingseinheit." }
            guard !(p[CoachParam.note] ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return "Die Notiz ist leer." }
        case .setSessionExertion:
            guard p[CoachParam.sessionID] != nil else { return "Bitte wähle die Trainingseinheit." }
            guard let value = CoachParam.double(p[CoachParam.exertion]), (1...10).contains(value) else {
                return "Die Belastung muss zwischen 1 und 10 liegen."
            }
        case .logSupplement:
            guard p[CoachParam.supplementID] != nil else { return "Supplement nicht gefunden." }
        case .setWaterTarget:
            guard let ml = CoachParam.double(p[CoachParam.ml]), (500...6000).contains(ml) else {
                return "Das Trinkziel muss zwischen 500 und 6000 ml liegen."
            }
        case .changeGoal:
            guard FitnessGoal(rawValue: p[CoachParam.goal] ?? "") != nil else { return "Unbekanntes Ziel." }
            if context.currentProfile() == nil { return "Kein Profil vorhanden." }
        case .deleteLastWeight, .deleteEntry:
            guard p[CoachParam.entityID] != nil else { return "Kein passender Eintrag gefunden." }
        case .navigate, .openSettings:
            guard p[CoachParam.destination] != nil || p[CoachParam.section] != nil else { return "Unbekanntes Ziel." }
            if p[CoachParam.destination] == "cycle" && !prefs.isEnabled(.cycle) {
                return "Das Zyklusmodul ist nicht aktiviert."
            }
        case .startWorkout, .searchEntries:
            break
        }
        return nil
    }
}

/// Führt bestätigte Aktionen aus, protokolliert sie und kann sie rückgängig machen.
@MainActor
struct ActionExecutor {
    let context: ModelContext
    let router: AppRouter
    let prefs: AppPreferences
    /// Schliesst den Coach (für Navigationsaktionen).
    var dismiss: () -> Void = {}

    /// Wendet eine Aktion an und gibt den neuen Zustand zurück.
    func apply(_ original: CoachAction) -> CoachAction {
        var action = original
        if let error = ActionValidator.validate(action, prefs: prefs, context: context) {
            action.status = .failed
            action.resultNote = error
            return action
        }
        let p = action.params

        switch action.kind {
        case .logWeight:
            guard let kg = CoachParam.double(p[CoachParam.kg]) else { break }
            let date = CoachParam.date(day: p[CoachParam.day], time: p[CoachParam.time])
            let note = p[CoachParam.time] == nil && !Calendar.current.isDateInToday(date) ? "Uhrzeit nicht angegeben" : ""
            let entry = LogService.logWeight(kg: kg, date: date, source: .coach, note: note, actor: .coach, in: context)
            link(&action, entityID: entry.id)

        case .logWater:
            guard let ml = CoachParam.double(p[CoachParam.ml]) else { break }
            let date = CoachParam.date(day: p[CoachParam.day], time: p[CoachParam.time])
            let entry = LogService.logWater(ml: ml, beverage: p[CoachParam.beverage] ?? "Wasser", date: date,
                                            source: .coach, actor: .coach, in: context)
            link(&action, entityID: entry.id)

        case .logFood:
            guard let grams = CoachParam.double(p[CoachParam.grams]) else { break }
            let date = CoachParam.date(day: p[CoachParam.day], time: p[CoachParam.time])
            let meal = MealType(rawValue: p[CoachParam.meal] ?? "") ?? .suggested(for: date)
            let label = "\(Fmt.decimal(grams)) g"
            if let id = UUID(uuidString: p[CoachParam.foodID] ?? ""),
               let food = try? context.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })).first {
                let entry = LogService.logFood(food, grams: grams, amountLabel: label, meal: meal, date: date,
                                               source: .coach, actor: .coach, in: context)
                link(&action, entityID: entry.id)
            } else {
                let per100 = Nutrients(kcal: CoachParam.double(p[CoachParam.kcal100]) ?? 0,
                                       protein: CoachParam.double(p[CoachParam.protein100]) ?? 0,
                                       carbs: CoachParam.double(p[CoachParam.carbs100]) ?? 0,
                                       fat: CoachParam.double(p[CoachParam.fat100]) ?? 0)
                let entry = LogService.logCustom(name: p[CoachParam.name] ?? "Lebensmittel", nutrients: per100.forGrams(grams),
                                                 grams: grams, amountLabel: label, meal: meal, date: date,
                                                 quality: .aiUnconfirmed, source: .photo, isEstimate: true,
                                                 actor: .coach, in: context)
                link(&action, entityID: entry.id)
            }

        case .logSupplement:
            guard let id = UUID(uuidString: p[CoachParam.supplementID] ?? ""),
                  let supplement = try? context.fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.id == id })).first
            else { break }
            let date = CoachParam.date(day: p[CoachParam.day], time: p[CoachParam.time])
            let intake = LogService.logIntake(supplement, date: date, source: .coach, actor: .coach, in: context)
            link(&action, entityID: intake.id)

        case .addWorkoutNote:
            guard let session = session(p[CoachParam.sessionID]) else { break }
            let note = (p[CoachParam.note] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            action.params[CoachParam.previous] = session.notes
            session.notes = session.notes.isEmpty ? note : "\(session.notes)\n\(note)"
            let log = AuditLog.record(context, actor: .coach, summary: "Notiz zu „\(session.name)“ hinzugefügt",
                                      detail: note, entityType: EntityType.workout, entityID: session.id.uuidString)
            action.auditEntryID = log.id
            context.saveQuietly()

        case .setSessionExertion:
            guard let session = session(p[CoachParam.sessionID]),
                  let value = CoachParam.double(p[CoachParam.exertion]) else { break }
            action.params[CoachParam.previous] = session.perceivedExertion.map { String($0) } ?? ""
            session.perceivedExertion = Int(value)
            let log = AuditLog.record(context, actor: .coach, summary: "Belastung für „\(session.name)“: \(Int(value))/10",
                                      entityType: EntityType.workout, entityID: session.id.uuidString)
            action.auditEntryID = log.id
            context.saveQuietly()

        case .setWaterTarget:
            guard let profile = context.currentProfile(), let ml = CoachParam.double(p[CoachParam.ml]) else { break }
            action.params[CoachParam.previous] = String(profile.waterTargetMl)
            profile.waterTargetMl = Int(ml)
            let log = AuditLog.record(context, actor: .coach, summary: "Trinkziel auf \(Fmt.volume(ml)) gesetzt",
                                      entityType: EntityType.profile)
            action.auditEntryID = log.id
            context.saveQuietly()
            WidgetBridge.refresh(context: context)

        case .changeGoal:
            guard let profile = context.currentProfile(), let goal = FitnessGoal(rawValue: p[CoachParam.goal] ?? "") else { break }
            action.params[CoachParam.previous] = profile.primaryGoalRaw
            action.params[CoachParam.previousGoals] = profile.goalsRaw.joined(separator: ",")
            // Ziele mit gegensätzlicher Energiestrategie werden ersetzt, andere bleiben erhalten.
            var goals = profile.goals.filter { $0.energyStrategy == .maintenance && $0 != goal && $0 != .maintain }
            goals.insert(goal, at: 0)
            ProfileService.changeGoals(goals, primary: goal, for: profile, in: context, actor: .coach)
            prefs.dashboardCards = DashboardCardKind.defaults(for: goal)

        case .deleteLastWeight:
            guard let id = UUID(uuidString: p[CoachParam.entityID] ?? ""),
                  let entry = try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })).first
            else { break }
            action.params[CoachParam.kg] = CoachParam.string(entry.kg)
            action.params[CoachParam.previous] = ISO8601DateFormatter().string(from: entry.date)
            let log = AuditLog.record(context, actor: .coach, summary: "Gewichtseintrag \(Fmt.decimal(entry.kg)) kg gelöscht",
                                      detail: Fmt.mediumDate(entry.date), entityType: EntityType.weight, entityID: entry.id.uuidString)
            action.auditEntryID = log.id
            context.delete(entry)
            context.saveQuietly()
            WidgetBridge.refresh(context: context)

        case .deleteEntry:
            guard let id = UUID(uuidString: p[CoachParam.entityID] ?? ""),
                  let entry = try? context.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.id == id })).first
            else { break }
            LogService.deleteFood(entry, actor: .coach, in: context)

        case .navigate, .openSettings:
            navigate(p)
            action.status = .applied
            return action

        case .startWorkout:
            dismiss()
            router.show(tab: .training)
            action.status = .applied
            return action

        case .searchEntries:
            break
        }

        action.status = .applied
        return action
    }

    /// Macht eine angewendete Aktion rückgängig.
    func undo(_ original: CoachAction) -> CoachAction {
        var action = original
        guard action.status == .applied else { return action }
        let p = action.params
        var success = false

        switch action.kind {
        case .logWeight, .logWater, .logFood, .logSupplement:
            if let auditID = action.auditEntryID,
               let log = try? context.fetch(FetchDescriptor<AuditLogEntry>(predicate: #Predicate { $0.id == auditID })).first {
                success = LogService.undo(log, in: context)
            }
        case .addWorkoutNote:
            if let session = session(p[CoachParam.sessionID]) {
                session.notes = p[CoachParam.previous] ?? ""
                success = true
            }
        case .setSessionExertion:
            if let session = session(p[CoachParam.sessionID]) {
                session.perceivedExertion = Int(p[CoachParam.previous] ?? "")
                success = true
            }
        case .setWaterTarget:
            if let profile = context.currentProfile(), let previous = Int(p[CoachParam.previous] ?? "") {
                profile.waterTargetMl = previous
                success = true
            }
        case .changeGoal:
            if let profile = context.currentProfile(), let previous = FitnessGoal(rawValue: p[CoachParam.previous] ?? "") {
                let goals = (p[CoachParam.previousGoals] ?? "").split(separator: ",").compactMap { FitnessGoal(rawValue: String($0)) }
                ProfileService.changeGoals(goals.isEmpty ? [previous] : goals, primary: previous, for: profile, in: context, actor: .user)
                prefs.dashboardCards = DashboardCardKind.defaults(for: previous)
                success = true
            }
        case .deleteLastWeight:
            if let kg = CoachParam.double(p[CoachParam.kg]),
               let date = ISO8601DateFormatter().date(from: p[CoachParam.previous] ?? "") {
                let entry = WeightEntry(kg: kg, date: date, source: .manual)
                context.insert(entry)
                success = true
            }
        default:
            break
        }

        guard success else {
            action.resultNote = "Rückgängig machen war nicht möglich."
            return action
        }
        if !(action.kind == .logWeight || action.kind == .logWater || action.kind == .logFood || action.kind == .logSupplement) {
            if let auditID = action.auditEntryID,
               let log = try? context.fetch(FetchDescriptor<AuditLogEntry>(predicate: #Predicate { $0.id == auditID })).first {
                log.isUndone = true
            }
            AuditLog.record(context, actor: .user, summary: "Rückgängig: \(action.title)", entityType: EntityType.settings)
            context.saveQuietly()
            WidgetBridge.refresh(context: context)
        }
        action.status = .undone
        return action
    }

    // MARK: Helfer

    /// Verknüpft die Aktion mit dem Protokolleintrag des erzeugten Datensatzes (für Rückgängig).
    private func link(_ action: inout CoachAction, entityID: UUID) {
        let idString = entityID.uuidString
        let optionalID: String? = idString
        var descriptor = FetchDescriptor<AuditLogEntry>(predicate: #Predicate { $0.entityID == optionalID },
                                                        sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        action.auditEntryID = (try? context.fetch(descriptor).first)?.id
        action.params[CoachParam.entityID] = idString
    }

    private func session(_ idString: String?) -> WorkoutSession? {
        guard let id = UUID(uuidString: idString ?? "") else { return nil }
        return try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first
    }

    private func navigate(_ p: [String: String]) {
        if let raw = p[CoachParam.section], let section = SettingsSection(rawValue: raw) {
            dismiss()
            router.open(.settingsSection(section))
            return
        }
        guard let destination = p[CoachParam.destination] else { return }
        if destination == "workoutSession", let id = UUID(uuidString: p[CoachParam.sessionID] ?? "") {
            dismiss()
            router.open(.workoutSession(id: id))
            return
        }
        if destination.hasPrefix("foodSearch") {
            let meal = MealType(rawValue: String(destination.dropFirst("foodSearch.".count))) ?? .suggested()
            router.present(.foodSearch(meal: meal, day: .now))
            return
        }
        if let target = CoachDestinations.destination(for: destination) {
            dismiss()
            router.open(target)
        } else if let tab = CoachDestinations.tab(for: destination) {
            dismiss()
            router.show(tab: tab)
        }
    }
}

/// Zuordnung von Navigationszielen (für lokale und serverseitige Aktionen).
enum CoachDestinations {
    static func destination(for key: String) -> AppDestination? {
        switch key {
        case "settings": .settings
        case "supplements": .supplements
        case "cycle": .cycle
        case "habits": .habits
        case "water": .water
        case "recipes": .recipes
        case "savedMeals": .savedMeals
        case "weight": .weight
        case "measurements": .measurements
        case "bodyAvatar": .bodyAvatar
        case "progressPhotos": .progressPhotos
        case "weeklyReport": .weeklyReport
        case "energyInsight": .energyInsight
        case "exerciseLibrary": .exerciseLibrary
        case "workoutHistory": .workoutHistory
        case "gymProfiles": .gymProfiles
        case "planGenerator": .planGenerator
        case "auditLog": .auditLog
        default: nil
        }
    }

    static func tab(for key: String) -> AppTab? {
        switch key {
        case "tab.today": .today
        case "tab.nutrition": .nutrition
        case "tab.training": .training
        case "tab.progress": .progress
        default: nil
        }
    }

    static func title(for key: String) -> String {
        switch key {
        case "settings": "Einstellungen"
        case "supplements": "Supplements"
        case "cycle": "Zyklus"
        case "habits": "Gewohnheiten"
        case "water": "Wasser"
        case "recipes": "Rezepte"
        case "savedMeals": "Gespeicherte Mahlzeiten"
        case "weight": "Gewicht"
        case "measurements": "Körpermasse"
        case "bodyAvatar": "3D-Körper"
        case "progressPhotos": "Fortschrittsfotos"
        case "weeklyReport": "Wochenanalyse"
        case "energyInsight": "Energiebedarf"
        case "exerciseLibrary": "Übungsbibliothek"
        case "workoutHistory": "Trainingshistorie"
        case "gymProfiles": "Studio-Profile"
        case "planGenerator": "Trainingsplan erstellen"
        case "auditLog": "Änderungsprotokoll"
        case "workoutSession": "Trainingseinheit"
        case "tab.today": "Heute"
        case "tab.nutrition": "Ernährung"
        case "tab.training": "Training"
        case "tab.progress": "Fortschritt"
        default: key.hasPrefix("foodSearch") ? "Lebensmittelsuche" : key
        }
    }
}
