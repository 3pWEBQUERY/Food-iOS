import Foundation
import SwiftData

/// Lokale Offline-Datenbank (SwiftData). Alle Kernfunktionen arbeiten ohne Internet.
/// Die Datei wird mit iOS Data Protection verschlüsselt gespeichert.
enum Persistence {
    static let schema = Schema([
        UserProfile.self, GoalPhase.self, Habit.self, HabitCheck.self, AuditLogEntry.self, CoachMessage.self,
        FoodItem.self, FoodLogEntry.self, Recipe.self, SavedMeal.self, WaterEntry.self,
        WeightEntry.self, BodyMeasurement.self, ProgressPhoto.self, CycleDay.self,
        Exercise.self, Equipment.self, GymProfile.self, WorkoutPlan.self, WorkoutTemplate.self,
        WorkoutSession.self, ExerciseLog.self, SetLog.self,
        Supplement.self, SupplementIntake.self
    ])

    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Kern.store")
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        do {
            if inMemory {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [config])
            }
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            applyFileProtection()
            return container
        } catch {
            // Fallback, damit die App nicht abstürzt. Der Fehler wird beim Start angezeigt.
            StartupDiagnostics.shared.storeError = error.localizedDescription
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }

    /// Schutzklasse „bis zur ersten Entsperrung“ – sicher, aber Erinnerungen
    /// und Widgets funktionieren weiterhin im Hintergrund.
    private static func applyFileProtection() {
        let dir = URL.applicationSupportDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("Kern.store") {
            try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        }
    }

    /// Container mit Beispieldaten für SwiftUI-Previews.
    @MainActor
    static var preview: ModelContainer = {
        let container = makeContainer(inMemory: true)
        let context = container.mainContext
        SeedService.seedIfNeeded(in: context)
        let profile = UserProfile()
        profile.displayName = "Alex"
        profile.goals = [.buildMuscle]
        profile.primaryGoal = .buildMuscle
        context.insert(profile)
        try? context.save()
        return container
    }()
}

final class StartupDiagnostics {
    static let shared = StartupDiagnostics()
    var storeError: String?
}

extension ModelContext {
    /// Das (einzige) Nutzerprofil.
    func currentProfile() -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    /// Speichert und ignoriert Fehler bewusst nicht: Fehler werden geloggt.
    func saveQuietly() {
        do { try save() } catch { print("SwiftData save error: \(error)") }
    }
}
