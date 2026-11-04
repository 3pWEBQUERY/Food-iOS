import SwiftUI
import SwiftData

/// Einheitliche Hauptnavigation: Heute · Ernährung · Erfassen · Training · Fortschritt.
/// Der KI-Coach ist über das Bottom-Accessory jederzeit erreichbar.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs
    @Environment(WorkoutStore.self) private var workouts
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router

        TabView(selection: tabSelection) {
            Tab("Heute", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $router.todayPath) {
                    TodayView()
                        .withAppDestinations()
                }
            }

            Tab("Ernährung", systemImage: "fork.knife", value: AppTab.nutrition) {
                NavigationStack(path: $router.nutritionPath) {
                    NutritionView()
                        .withAppDestinations()
                }
            }

            Tab("Erfassen", systemImage: "plus.circle", value: AppTab.quickAdd) {
                Color.clear
            }

            Tab("Training", systemImage: "dumbbell", value: AppTab.training) {
                NavigationStack(path: $router.trainingPath) {
                    TrainingView()
                        .withAppDestinations()
                }
            }

            Tab("Fortschritt", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                NavigationStack(path: $router.progressPath) {
                    ProgressHubView()
                        .withAppDestinations()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            BottomAccessoryView()
        }
        .sheet(item: $router.sheet) { sheet in
            AppSheetView(sheet: sheet)
        }
        .fullScreenCover(isPresented: $router.isWorkoutPresented) {
            ActiveWorkoutView()
        }
        .overlay {
            if !prefs.hasSeenTutorial {
                TutorialOverlay()
                    .transition(.opacity)
            }
        }
        .onOpenURL { router.handle(url: $0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else {
                if phase == .background { WidgetBridge.refresh(context: context) }
                return
            }
            WidgetBridge.ingestPendingActions(context: context)
            WidgetBridge.refresh(context: context)
            if prefs.healthKitEnabled {
                Task {
                    await health.refreshToday()
                    _ = await health.importWeights(into: context)
                }
            }
        }
    }

    /// Der mittlere Tab öffnet die Schnellerfassung, statt den Tab zu wechseln.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { newValue in
                if newValue == .quickAdd {
                    router.present(.quickAdd)
                } else {
                    router.selectedTab = newValue
                }
            }
        )
    }
}

/// Inhalt des Bottom-Accessory: laufendes Training oder Coach-Zugang.
private struct BottomAccessoryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if workouts.hasActiveSession {
            ActiveWorkoutAccessory()
        } else {
            Button {
                router.present(.coach(prefill: nil))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(placement == .inline ? "Coach" : "Coach fragen oder etwas erfassen …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if placement != .inline {
                        Image(systemName: "mic")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("KI-Coach öffnen")
        }
    }
}

/// Zuordnung der Sheets zu ihren Ansichten.
struct AppSheetView: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .quickAdd:
            QuickAddSheet()
                .presentationDetents([.medium, .large])
        case .coach(let prefill):
            CoachView(prefill: prefill)
        case .foodSearch(let meal, let day):
            FoodSearchView(meal: meal, day: day)
        case .barcode(let meal, let day):
            BarcodeScannerSheet(meal: meal, day: day)
        case .photoFood(let meal, let day):
            PhotoFoodSheet(meal: meal, day: day)
        case .water:
            WaterQuickSheet()
                .presentationDetents([.medium])
        case .weightEntry:
            WeightEntrySheet()
                .presentationDetents([.medium])
        case .measurementEntry:
            MeasurementEntrySheet()
        case .dashboardEditor:
            DashboardEditorView()
        case .settings:
            NavigationStack {
                SettingsView()
                    .withAppDestinations()
            }
        }
    }
}

extension View {
    /// Registriert alle Push-Ziele der App.
    func withAppDestinations() -> some View {
        navigationDestination(for: AppDestination.self) { destination in
            AppDestinationView(destination: destination)
        }
    }
}

struct AppDestinationView: View {
    let destination: AppDestination

    var body: some View {
        switch destination {
        case .settings: SettingsView()
        case .settingsSection(let section): SettingsSectionView(section: section)
        case .supplements: SupplementsView()
        case .cycle: CycleView()
        case .habits: HabitsView()
        case .water: WaterView()
        case .recipes: RecipesView()
        case .savedMeals: SavedMealsView()
        case .weight: WeightView()
        case .measurements: MeasurementsView()
        case .bodyAvatar: BodyAvatarView()
        case .progressPhotos: ProgressPhotosView()
        case .weeklyReport: WeeklyReportView()
        case .energyInsight: EnergyInsightView()
        case .exerciseLibrary: ExerciseLibraryView()
        case .exercise(let id): ExerciseDetailView(exerciseID: id)
        case .workoutHistory: WorkoutHistoryView()
        case .workoutSession(let id): WorkoutSessionDetailView(sessionID: id)
        case .gymProfiles: GymProfilesView()
        case .planGenerator: PlanGeneratorView()
        case .plan(let id): PlanDetailView(planID: id)
        case .auditLog: AuditLogView()
        }
    }
}
