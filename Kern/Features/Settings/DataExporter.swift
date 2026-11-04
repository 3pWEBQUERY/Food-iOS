import Foundation
import SwiftData
import WidgetKit

/// Vollständiger Datenexport (JSON/CSV) und vollständige Datenlöschung.
@MainActor
enum DataExporter {
    enum ExportError: LocalizedError {
        case encoding
        var errorDescription: String? { "Der Export konnte nicht erstellt werden." }
    }

    // MARK: JSON

    /// Erstellt einen vollständigen Export aller lokal gespeicherten Daten.
    /// Fotos werden als Metadaten exportiert (Bilddateien separat über die Fotoansicht).
    static func exportJSON(context: ModelContext, prefs: AppPreferences) throws -> URL {
        let iso = ISO8601DateFormatter()
        func d(_ date: Date?) -> Any { date.map { iso.string(from: $0) } ?? NSNull() }
        func o(_ value: Any?) -> Any { value ?? NSNull() }
        func encoded<T: Encodable>(_ value: T) -> Any {
            guard let data = try? JSONEncoder().encode(value),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
            return object
        }
        func all<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        var root: [String: Any] = [
            "format": "kern-export",
            "version": 1,
            "exportedAt": iso.string(from: .now),
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        ]

        root["settings"] = [
            "modules": prefs.enabledModules.map(\.rawValue).sorted(),
            "dashboard": prefs.dashboardCards.map(\.rawValue),
            "weightUnit": prefs.weightUnit.rawValue,
            "energyUnit": prefs.energyUnit.rawValue,
            "aiProcessingConsent": prefs.aiProcessingConsent,
            "cycleAnalysisConsent": prefs.cycleAnalysisConsent,
            "healthKitEnabled": prefs.healthKitEnabled,
            "coachAutomations": Array(prefs.coachAutomations).sorted()
        ] as [String: Any]

        root["profile"] = all(UserProfile.self).map { p -> [String: Any] in
            [
                "id": p.id.uuidString, "createdAt": d(p.createdAt), "displayName": p.displayName,
                "birthDate": d(p.birthDate), "genderIdentity": p.genderIdentity, "physiologicalSex": p.physiologicalSexRaw,
                "heightCm": p.heightCm, "startWeightKg": p.startWeightKg, "bodyFatPercent": o(p.bodyFatPercent),
                "activityLevel": p.activityLevelRaw, "specialSituation": p.specialSituationRaw,
                "trainingExperience": p.trainingExperienceRaw, "trainingDaysPerWeek": p.trainingDaysPerWeek,
                "sessionDurationMin": p.sessionDurationMin, "trainingLocation": p.trainingLocationRaw,
                "preferredMethods": p.preferredMethods, "strengths": p.strengths, "weaknesses": p.weaknesses,
                "adaptationsNote": p.adaptationsNote, "loadLimitsNote": p.loadLimitsNote,
                "excludedExerciseIDs": p.excludedExerciseIDs, "professionalGuidelines": p.professionalGuidelines,
                "goals": p.goalsRaw, "primaryGoal": p.primaryGoalRaw, "targetWeightKg": o(p.targetWeightKg),
                "weeklyRateKg": p.weeklyRateKg, "dietType": p.dietTypeRaw, "allergies": p.allergies,
                "excludedFoods": p.excludedFoods, "preferredFoods": p.preferredFoods, "mealsPerDay": p.mealsPerDay,
                "energyFormula": p.energyFormulaRaw, "calorieTarget": p.calorieTarget, "proteinTargetG": p.proteinTargetG,
                "carbTargetG": p.carbTargetG, "fatTargetG": p.fatTargetG, "fiberTargetG": p.fiberTargetG,
                "waterTargetMl": p.waterTargetMl, "stepsTarget": p.stepsTarget, "weeklyWorkoutTarget": p.weeklyWorkoutTarget,
                "targetsAreManual": p.targetsAreManual, "adaptiveTDEE": o(p.adaptiveTDEE)
            ]
        }

        root["goalPhases"] = all(GoalPhase.self).map { g -> [String: Any] in
            ["id": g.id.uuidString, "startDate": d(g.startDate), "endDate": d(g.endDate), "goals": g.goalsRaw,
             "primaryGoal": g.primaryGoalRaw, "calorieTarget": g.calorieTarget, "proteinTargetG": g.proteinTargetG,
             "startWeightKg": o(g.startWeightKg), "targetWeightKg": o(g.targetWeightKg), "note": g.note]
        }

        root["foodLog"] = all(FoodLogEntry.self).sorted { $0.date < $1.date }.map { e -> [String: Any] in
            ["id": e.id.uuidString, "date": d(e.date), "meal": e.mealRaw, "name": e.name, "brand": o(e.brand),
             "grams": e.grams, "amountLabel": e.amountLabel, "per100": encoded(e.per100), "total": encoded(e.nutrients),
             "quality": e.qualityRaw, "source": e.sourceRaw, "isEstimate": e.isEstimate, "foodID": o(e.foodID?.uuidString),
             "recipeID": o(e.recipeID?.uuidString), "note": e.note]
        }

        root["customFoods"] = all(FoodItem.self).filter { $0.source == .user || $0.source == .ai || $0.isFavorite }.map { f -> [String: Any] in
            ["id": f.id.uuidString, "name": f.name, "brand": o(f.brand), "barcode": o(f.barcode), "source": f.sourceRaw,
             "quality": f.qualityRaw, "per100": encoded(f.per100), "servings": encoded(f.servings), "isLiquid": f.isLiquid,
             "isFavorite": f.isFavorite, "licenseNote": o(f.licenseNote)]
        }

        root["recipes"] = all(Recipe.self).map { r -> [String: Any] in
            ["id": r.id.uuidString, "name": r.name, "servings": r.servings, "cookedWeightG": o(r.cookedWeightG),
             "ingredients": encoded(r.ingredients), "instructions": r.instructions]
        }

        root["savedMeals"] = all(SavedMeal.self).map { m -> [String: Any] in
            ["id": m.id.uuidString, "name": m.name, "meal": m.mealRaw, "items": encoded(m.items)]
        }

        root["water"] = all(WaterEntry.self).sorted { $0.date < $1.date }.map { w -> [String: Any] in
            ["id": w.id.uuidString, "date": d(w.date), "ml": w.ml, "beverage": w.beverage, "source": w.sourceRaw]
        }

        root["weights"] = all(WeightEntry.self).sorted { $0.date < $1.date }.map { w -> [String: Any] in
            ["id": w.id.uuidString, "date": d(w.date), "kg": w.kg, "source": w.sourceRaw, "note": w.note]
        }

        root["measurements"] = all(BodyMeasurement.self).sorted { $0.date < $1.date }.map { m -> [String: Any] in
            var dict: [String: Any] = ["id": m.id.uuidString, "date": d(m.date), "note": m.note,
                                       "bodyFatPercent": o(m.bodyFatPercent)]
            for field in BodyMeasurement.fields { dict[field.key] = o(m.value(for: field.key)) }
            return dict
        }

        root["progressPhotos"] = all(ProgressPhoto.self).map { p -> [String: Any] in
            ["id": p.id.uuidString, "date": d(p.date), "pose": p.poseRaw, "note": p.note, "bytes": p.imageData.count]
        }

        root["cycle"] = all(CycleDay.self).sorted { $0.date < $1.date }.map { c -> [String: Any] in
            ["day": c.dayKey, "flow": c.flowRaw, "symptoms": c.symptomsRaw, "energy": c.energy, "mood": c.mood,
             "exertionCapacity": c.exertionCapacity, "note": c.note]
        }

        root["workoutPlans"] = all(WorkoutPlan.self).map { plan -> [String: Any] in
            ["id": plan.id.uuidString, "name": plan.name, "isActive": plan.isActive, "source": plan.sourceRaw,
             "goal": plan.goalRaw, "daysPerWeek": plan.daysPerWeek, "rationale": plan.rationale, "notes": plan.notes,
             "templates": plan.sortedTemplates.map { t -> [String: Any] in
                 ["id": t.id.uuidString, "name": t.name, "order": t.order, "exercises": encoded(t.exercises), "notes": t.notes]
             }]
        }

        root["workouts"] = all(WorkoutSession.self).sorted { $0.startedAt < $1.startedAt }.map { s -> [String: Any] in
            ["id": s.id.uuidString, "name": s.name, "startedAt": d(s.startedAt), "endedAt": d(s.endedAt),
             "notes": s.notes, "perceivedExertion": o(s.perceivedExertion), "dayForm": o(s.dayForm),
             "isCompleted": s.isCompleted,
             "exercises": s.sortedExercises.map { e -> [String: Any] in
                 ["exerciseID": e.exerciseID, "name": e.exerciseName, "equipmentID": o(e.equipmentID),
                  "equipment": o(e.equipmentLabel), "notes": e.notes, "supersetGroup": o(e.supersetGroup),
                  "sets": e.sortedSets.map { set -> [String: Any] in
                      ["kind": set.kindRaw, "weightKg": set.weightKg, "reps": set.reps, "targetReps": o(set.targetReps),
                       "rpe": o(set.rpe), "rir": o(set.rir), "durationSec": o(set.durationSec),
                       "isCompleted": set.isCompleted, "completedAt": d(set.completedAt)]
                  }]
             }]
        }

        root["customExercises"] = all(Exercise.self).filter(\.isCustom).map { e -> [String: Any] in
            ["id": e.id, "name": e.name, "primaryMuscle": e.primaryMuscleRaw, "equipment": e.equipmentKindRaw]
        }

        root["gyms"] = all(GymProfile.self).map { g -> [String: Any] in
            ["id": g.id.uuidString, "name": g.name, "equipmentIDs": g.equipmentIDs, "availableKinds": g.availableKindsRaw, "notes": g.notes]
        }

        root["supplements"] = all(Supplement.self).map { s -> [String: Any] in
            ["id": s.id.uuidString, "name": s.name, "brand": s.brand, "form": s.formRaw, "servingLabel": s.servingLabel,
             "ingredients": encoded(s.ingredients), "isActive": s.isActive, "frequency": s.frequencyRaw,
             "weekdays": s.weekdays, "scheduleMinutes": s.scheduleMinutes, "servingsPerIntake": s.servingsPerIntake,
             "stockServings": o(s.stockServings), "notes": s.notes]
        }

        root["supplementIntakes"] = all(SupplementIntake.self).sorted { $0.date < $1.date }.map { i -> [String: Any] in
            ["supplementID": i.supplementID.uuidString, "name": i.supplementName, "date": d(i.date), "servings": i.servings]
        }

        root["habits"] = all(Habit.self).map { h -> [String: Any] in
            ["id": h.id.uuidString, "name": h.name, "symbol": h.symbol, "isArchived": h.isArchived]
        }
        root["habitChecks"] = all(HabitCheck.self).map { c -> [String: Any] in
            ["habitID": c.habitID.uuidString, "day": c.dayKey]
        }

        root["coachMessages"] = all(CoachMessage.self).sorted { $0.date < $1.date }.map { m -> [String: Any] in
            ["date": d(m.date), "role": m.roleRaw, "text": m.text, "hasImage": m.imageData != nil]
        }

        root["auditLog"] = all(AuditLogEntry.self).sorted { $0.date < $1.date }.map { a -> [String: Any] in
            ["date": d(a.date), "actor": a.actorRaw, "summary": a.summary, "detail": a.detail,
             "entityType": a.entityType, "entityID": o(a.entityID), "isUndone": a.isUndone]
        }

        guard JSONSerialization.isValidJSONObject(root) else { throw ExportError.encoding }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let url = exportDirectory().appending(path: "Kern-Export-\(DayKey.today).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: CSV

    static func exportWeightsCSV(context: ModelContext) throws -> URL {
        let entries = ((try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))) ?? [])
        let iso = ISO8601DateFormatter()
        var csv = "datum;gewicht_kg;quelle;notiz\n"
        for e in entries {
            csv += "\(iso.string(from: e.date));\(e.kg);\(e.sourceRaw);\(escape(e.note))\n"
        }
        return try write(csv, name: "Kern-Gewicht-\(DayKey.today).csv")
    }

    static func exportFoodCSV(context: ModelContext) throws -> URL {
        let entries = ((try? context.fetch(FetchDescriptor<FoodLogEntry>(sortBy: [SortDescriptor(\.date)]))) ?? [])
        let iso = ISO8601DateFormatter()
        var csv = "datum;mahlzeit;lebensmittel;marke;menge_g;kcal;protein_g;kohlenhydrate_g;fett_g;ballaststoffe_g;zucker_g;salz_g;qualitaet;schaetzung\n"
        for e in entries {
            let n = e.nutrients
            let row: [String] = [
                iso.string(from: e.date), e.mealRaw, escape(e.name), escape(e.brand ?? ""),
                String(format: "%.1f", e.grams), String(format: "%.1f", n.kcal), String(format: "%.1f", n.protein),
                String(format: "%.1f", n.carbs), String(format: "%.1f", n.fat),
                n.fiber.map { String(format: "%.1f", $0) } ?? "", n.sugar.map { String(format: "%.1f", $0) } ?? "",
                n.salt.map { String(format: "%.2f", $0) } ?? "", e.qualityRaw, e.isEstimate ? "ja" : "nein"
            ]
            csv += row.joined(separator: ";") + "\n"
        }
        return try write(csv, name: "Kern-Ernaehrung-\(DayKey.today).csv")
    }

    private static func escape(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: " ")
        return cleaned.contains(";") ? "\"\(cleaned)\"" : cleaned
    }

    private static func write(_ text: String, name: String) throws -> URL {
        let url = exportDirectory().appending(path: name)
        guard let data = text.data(using: .utf8) else { throw ExportError.encoding }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static func exportDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "KernExport", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Entfernt temporäre Exportdateien.
    static func cleanUpExports() {
        try? FileManager.default.removeItem(at: exportDirectory())
    }

    // MARK: Löschen

    /// Löscht alle persönlichen Daten unwiderruflich und setzt die App zurück.
    static func deleteAllData(context: ModelContext, prefs: AppPreferences) {
        func wipe<T: PersistentModel>(_ type: T.Type) {
            let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for item in items { context.delete(item) }
        }
        // Abhängige Datensätze zuerst
        wipe(SetLog.self)
        wipe(ExerciseLog.self)
        wipe(WorkoutSession.self)
        wipe(WorkoutTemplate.self)
        wipe(WorkoutPlan.self)
        wipe(FoodLogEntry.self)
        wipe(WaterEntry.self)
        wipe(Recipe.self)
        wipe(SavedMeal.self)
        wipe(FoodItem.self)
        wipe(WeightEntry.self)
        wipe(BodyMeasurement.self)
        wipe(ProgressPhoto.self)
        wipe(CycleDay.self)
        wipe(SupplementIntake.self)
        wipe(Supplement.self)
        wipe(HabitCheck.self)
        wipe(Habit.self)
        wipe(CoachMessage.self)
        wipe(AuditLogEntry.self)
        wipe(GoalPhase.self)
        wipe(GymProfile.self)
        wipe(Equipment.self)
        wipe(Exercise.self)
        wipe(UserProfile.self)
        context.saveQuietly()

        KeychainStore.removeAll()
        NotificationManager.cancelAll()
        WidgetSnapshot.sharedDefaults?.removeObject(forKey: WidgetSnapshot.storageKey)
        _ = WidgetPendingActions.takeWater()
        WidgetCenter.shared.reloadAllTimelines()
        cleanUpExports()

        // Basisdaten (Lebensmittel-Referenzwerte, Übungen) neu anlegen.
        UserDefaults.standard.removeObject(forKey: "kern.seed.version")
        SeedService.seedIfNeeded(in: context)

        prefs.resetAll()
    }
}
