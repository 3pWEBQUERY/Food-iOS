import Foundation
import Observation

enum AppTab: Hashable {
    case today, nutrition, quickAdd, training, progress
}

/// Modal präsentierte Bereiche. Jede Sheet-View bringt ihren eigenen NavigationStack mit.
enum AppSheet: Identifiable, Hashable {
    case quickAdd
    case coach(prefill: String?)
    case foodSearch(meal: MealType, day: Date)
    case barcode(meal: MealType, day: Date)
    case photoFood(meal: MealType, day: Date)
    case water
    case weightEntry
    case measurementEntry
    case dashboardEditor
    case settings

    var id: String {
        switch self {
        case .quickAdd: "quickAdd"
        case .coach(let prefill): "coach-\(prefill ?? "")"
        case .foodSearch(let meal, let day): "food-\(meal.rawValue)-\(DayKey.make(day))"
        case .barcode(let meal, let day): "barcode-\(meal.rawValue)-\(DayKey.make(day))"
        case .photoFood(let meal, let day): "photo-\(meal.rawValue)-\(DayKey.make(day))"
        case .water: "water"
        case .weightEntry: "weight"
        case .measurementEntry: "measurement"
        case .dashboardEditor: "dashboard"
        case .settings: "settings"
        }
    }
}

/// Ziele für Push-Navigation innerhalb der Tabs.
enum AppDestination: Hashable {
    case settings
    case settingsSection(SettingsSection)
    case supplements
    case cycle
    case habits
    case water
    case recipes
    case savedMeals
    case weight
    case measurements
    case bodyAvatar
    case progressPhotos
    case weeklyReport
    case energyInsight
    case exerciseLibrary
    case exercise(id: String)
    case workoutHistory
    case workoutSession(id: UUID)
    case gymProfiles
    case planGenerator
    case plan(id: UUID)
    case auditLog

    /// Tab, in dem dieses Ziel geöffnet wird.
    var homeTab: AppTab {
        switch self {
        case .settings, .settingsSection, .supplements, .cycle, .habits, .auditLog: .today
        case .water, .recipes, .savedMeals: .nutrition
        case .weight, .measurements, .bodyAvatar, .progressPhotos, .weeklyReport, .energyInsight: .progress
        case .exerciseLibrary, .exercise, .workoutHistory, .workoutSession, .gymProfiles, .planGenerator, .plan: .training
        }
    }
}

/// Zentrale Navigation – wird auch vom KI-Coach verwendet, um Bereiche zu öffnen.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var sheet: AppSheet?
    var isWorkoutPresented = false

    var todayPath: [AppDestination] = []
    var nutritionPath: [AppDestination] = []
    var trainingPath: [AppDestination] = []
    var progressPath: [AppDestination] = []

    /// Im Ernährungstagebuch ausgewählter Tag.
    var nutritionDay: Date = .now

    /// Präsentiert ein Sheet. Ist bereits eines offen, wird es zuerst geschlossen.
    func present(_ newSheet: AppSheet) {
        if sheet == nil {
            sheet = newSheet
            return
        }
        sheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.sheet = newSheet
        }
    }

    func dismissSheet() { sheet = nil }

    /// Öffnet ein Ziel im passenden Tab.
    func open(_ destination: AppDestination) {
        sheet = nil
        let tab = destination.homeTab
        selectedTab = tab
        switch tab {
        case .today: todayPath = [destination]
        case .nutrition: nutritionPath = [destination]
        case .training: trainingPath = [destination]
        case .progress: progressPath = [destination]
        case .quickAdd: break
        }
    }

    func show(tab: AppTab) {
        sheet = nil
        selectedTab = tab
    }

    /// Deep Links aus Widgets und Schnellaktionen, z. B. `kern://log/food`.
    func handle(url: URL) {
        guard url.scheme == "kern" else { return }
        let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        switch parts.joined(separator: "/") {
        case "log/food": present(.foodSearch(meal: .suggested(), day: .now))
        case "log/barcode": present(.barcode(meal: .suggested(), day: .now))
        case "log/water": present(.water)
        case "log/weight": present(.weightEntry)
        case "coach": present(.coach(prefill: nil))
        case "today": show(tab: .today)
        case "nutrition": show(tab: .nutrition)
        case "training": show(tab: .training)
        case "progress": show(tab: .progress)
        default: break
        }
    }
}
