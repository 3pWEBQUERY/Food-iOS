import SwiftUI
import SwiftData

@main
struct KernApp: App {
    @State private var preferences = AppPreferences.shared
    @State private var router = AppRouter()
    @State private var workoutStore = WorkoutStore()
    @State private var health = HealthKitManager.shared

    private let container = Persistence.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .environment(router)
                .environment(workoutStore)
                .environment(health)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

/// Entscheidet zwischen Onboarding und Hauptansicht.
struct RootView: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if prefs.hasCompletedOnboarding, !profiles.isEmpty {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: prefs.hasCompletedOnboarding)
        .task {
            SeedService.seedIfNeeded(in: context)
        }
    }
}
