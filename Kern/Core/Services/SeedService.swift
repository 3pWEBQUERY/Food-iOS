import Foundation
import SwiftData

/// Befüllt die lokale Datenbank beim ersten Start mit Basisdaten
/// (Lebensmittel-Referenzwerte, Übungen, Geräte).
@MainActor
enum SeedService {
    private static let seedVersionKey = "kern.seed.version"
    private static let currentSeedVersion = 1

    static func seedIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        let installed = defaults.integer(forKey: seedVersionKey)
        guard installed < currentSeedVersion else { return }

        let foodCount = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        if foodCount == 0 {
            for item in FoodSeed.makeItems() { context.insert(item) }
        }

        let exerciseCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        if exerciseCount == 0 {
            for exercise in ExerciseSeed.makeExercises() { context.insert(exercise) }
            for equipment in ExerciseSeed.makeEquipment() { context.insert(equipment) }
        }

        let gymCount = (try? context.fetchCount(FetchDescriptor<GymProfile>())) ?? 0
        if gymCount == 0 {
            context.insert(GymProfile(name: "Mein Studio", kinds: EquipmentKind.allCases, isDefault: true))
        }

        context.saveQuietly()
        defaults.set(currentSeedVersion, forKey: seedVersionKey)
    }
}
