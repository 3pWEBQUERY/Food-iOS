import Foundation
import Observation

/// Geräteweite Einstellungen (UserDefaults). Gesundheitsdaten liegen nicht hier,
/// sondern in der verschlüsselten SwiftData-Datenbank.
@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Lebenszyklus
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    var hasSeenTutorial: Bool { didSet { defaults.set(hasSeenTutorial, forKey: Keys.tutorial) } }
    /// Testmodus ohne Konto: lokal, ohne Cloud-Funktionen.
    var isGuestMode: Bool { didSet { defaults.set(isGuestMode, forKey: Keys.guest) } }

    // MARK: Personalisierung
    var enabledModules: Set<AppModule> { didSet { store(enabledModules.map(\.rawValue), Keys.modules) } }
    var dashboardCards: [DashboardCardKind] { didSet { store(dashboardCards.map(\.rawValue), Keys.dashboard) } }
    var weightUnit: WeightUnit { didSet { defaults.set(weightUnit.rawValue, forKey: Keys.weightUnit) } }
    var energyUnit: EnergyUnit { didSet { defaults.set(energyUnit.rawValue, forKey: Keys.energyUnit) } }
    var waterQuickAmounts: [Int] { didSet { store(waterQuickAmounts, Keys.waterQuick) } }

    // MARK: Datenschutz & KI
    /// Separate Zustimmung zur serverseitigen KI-Verarbeitung sensibler Daten.
    var aiProcessingConsent: Bool { didSet { defaults.set(aiProcessingConsent, forKey: Keys.aiConsent) } }
    /// Zyklusdaten dürfen für Auswertungen (z. B. Zusammenhang mit Training) genutzt werden.
    var cycleAnalysisConsent: Bool { didSet { defaults.set(cycleAnalysisConsent, forKey: Keys.cycleConsent) } }
    /// Sensible Module (Zyklus, Fotos) mit Face ID schützen.
    var lockSensitiveModules: Bool { didSet { defaults.set(lockSensitiveModules, forKey: Keys.lockSensitive) } }
    /// Vom Nutzer ausdrücklich freigegebene Coach-Automatisierungen (z. B. "water.autoApply").
    var coachAutomations: Set<String> { didSet { store(Array(coachAutomations), Keys.automations) } }

    // MARK: Apple Health
    var healthKitEnabled: Bool { didSet { defaults.set(healthKitEnabled, forKey: Keys.health) } }
    /// Aktivitätskalorien aus Health zum Budget addieren. Standardmässig aus,
    /// weil der Aktivitätsfaktor sie bereits enthält (keine Doppelzählung).
    var addActiveEnergyToBudget: Bool { didSet { defaults.set(addActiveEnergyToBudget, forKey: Keys.activeEnergy) } }

    // MARK: Training
    var defaultRestSeconds: Int { didSet { defaults.set(defaultRestSeconds, forKey: Keys.rest) } }
    var autoStartRestTimer: Bool { didSet { defaults.set(autoStartRestTimer, forKey: Keys.autoRest) } }
    var activeGymID: String? { didSet { defaults.set(activeGymID, forKey: Keys.activeGym) } }

    // MARK: Zyklus
    var cycleLengthDays: Int { didSet { defaults.set(cycleLengthDays, forKey: Keys.cycleLength) } }
    var periodLengthDays: Int { didSet { defaults.set(periodLengthDays, forKey: Keys.periodLength) } }

    // MARK: Erinnerungen
    var waterReminderEnabled: Bool { didSet { defaults.set(waterReminderEnabled, forKey: Keys.waterReminder) } }
    var weighInReminderEnabled: Bool { didSet { defaults.set(weighInReminderEnabled, forKey: Keys.weighReminder) } }
    var mealReminderEnabled: Bool { didSet { defaults.set(mealReminderEnabled, forKey: Keys.mealReminder) } }

    // MARK: Konto & Backend
    var appleUserID: String? { didSet { defaults.set(appleUserID, forKey: Keys.appleUser) } }
    /// Basis-URL des Kern-Backends (Railway). Leer = rein lokaler Betrieb.
    var backendBaseURL: String { didSet { defaults.set(backendBaseURL, forKey: Keys.backend) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        hasSeenTutorial = defaults.bool(forKey: Keys.tutorial)
        isGuestMode = defaults.bool(forKey: Keys.guest)

        let modules = (defaults.stringArray(forKey: Keys.modules) ?? []).compactMap(AppModule.init(rawValue:))
        enabledModules = defaults.object(forKey: Keys.modules) == nil
            ? [.nutrition, .water, .training, .measurements]
            : Set(modules)
        let cards = (defaults.stringArray(forKey: Keys.dashboard) ?? []).compactMap(DashboardCardKind.init(rawValue:))
        dashboardCards = cards.isEmpty ? DashboardCardKind.defaults(for: .healthierLife) : cards
        weightUnit = WeightUnit(rawValue: defaults.string(forKey: Keys.weightUnit) ?? "") ?? .kg
        energyUnit = EnergyUnit(rawValue: defaults.string(forKey: Keys.energyUnit) ?? "") ?? .kcal
        let quick = defaults.array(forKey: Keys.waterQuick) as? [Int] ?? []
        waterQuickAmounts = quick.isEmpty ? [250, 330, 500] : quick

        aiProcessingConsent = defaults.bool(forKey: Keys.aiConsent)
        cycleAnalysisConsent = defaults.bool(forKey: Keys.cycleConsent)
        lockSensitiveModules = defaults.bool(forKey: Keys.lockSensitive)
        coachAutomations = Set(defaults.stringArray(forKey: Keys.automations) ?? [])

        healthKitEnabled = defaults.bool(forKey: Keys.health)
        addActiveEnergyToBudget = defaults.bool(forKey: Keys.activeEnergy)

        let rest = defaults.integer(forKey: Keys.rest)
        defaultRestSeconds = rest == 0 ? 90 : rest
        autoStartRestTimer = defaults.object(forKey: Keys.autoRest) == nil ? true : defaults.bool(forKey: Keys.autoRest)
        activeGymID = defaults.string(forKey: Keys.activeGym)

        let cycle = defaults.integer(forKey: Keys.cycleLength)
        cycleLengthDays = cycle == 0 ? 28 : cycle
        let period = defaults.integer(forKey: Keys.periodLength)
        periodLengthDays = period == 0 ? 5 : period

        waterReminderEnabled = defaults.bool(forKey: Keys.waterReminder)
        weighInReminderEnabled = defaults.bool(forKey: Keys.weighReminder)
        mealReminderEnabled = defaults.bool(forKey: Keys.mealReminder)

        appleUserID = defaults.string(forKey: Keys.appleUser)
        backendBaseURL = defaults.string(forKey: Keys.backend) ?? ""
    }

    // MARK: Helfer

    func isEnabled(_ module: AppModule) -> Bool { enabledModules.contains(module) }

    func setModule(_ module: AppModule, enabled: Bool) {
        if enabled { enabledModules.insert(module) } else { enabledModules.remove(module) }
    }

    /// Dashboard-Karten, deren Modul aktiv ist, in Nutzerreihenfolge.
    var visibleDashboardCards: [DashboardCardKind] {
        dashboardCards.filter { card in
            guard let module = card.requiredModule else { return true }
            return enabledModules.contains(module)
        }
    }

    var hasBackend: Bool { URL(string: backendBaseURL)?.host != nil }

    /// Setzt alle lokalen Einstellungen zurück (z. B. nach vollständiger Datenlöschung).
    func resetAll() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        let fresh = AppPreferences(defaults: defaults)
        hasCompletedOnboarding = fresh.hasCompletedOnboarding
        hasSeenTutorial = fresh.hasSeenTutorial
        isGuestMode = fresh.isGuestMode
        enabledModules = fresh.enabledModules
        dashboardCards = fresh.dashboardCards
        weightUnit = fresh.weightUnit
        energyUnit = fresh.energyUnit
        waterQuickAmounts = fresh.waterQuickAmounts
        aiProcessingConsent = false
        cycleAnalysisConsent = false
        lockSensitiveModules = false
        coachAutomations = []
        healthKitEnabled = false
        addActiveEnergyToBudget = false
        defaultRestSeconds = 90
        autoStartRestTimer = true
        activeGymID = nil
        cycleLengthDays = 28
        periodLengthDays = 5
        waterReminderEnabled = false
        weighInReminderEnabled = false
        mealReminderEnabled = false
        appleUserID = nil
        backendBaseURL = ""
    }

    private func store<T>(_ value: [T], _ key: String) {
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let onboarding = "kern.onboarding.done"
        static let tutorial = "kern.tutorial.seen"
        static let guest = "kern.guest"
        static let modules = "kern.modules"
        static let dashboard = "kern.dashboard"
        static let weightUnit = "kern.unit.weight"
        static let energyUnit = "kern.unit.energy"
        static let waterQuick = "kern.water.quick"
        static let aiConsent = "kern.consent.ai"
        static let cycleConsent = "kern.consent.cycle"
        static let lockSensitive = "kern.lock.sensitive"
        static let automations = "kern.coach.automations"
        static let health = "kern.health.enabled"
        static let activeEnergy = "kern.health.activeEnergy"
        static let rest = "kern.training.rest"
        static let autoRest = "kern.training.autoRest"
        static let activeGym = "kern.training.gym"
        static let cycleLength = "kern.cycle.length"
        static let periodLength = "kern.cycle.period"
        static let waterReminder = "kern.reminder.water"
        static let weighReminder = "kern.reminder.weigh"
        static let mealReminder = "kern.reminder.meal"
        static let appleUser = "kern.account.apple"
        static let backend = "kern.backend.url"

        static let all = [onboarding, tutorial, guest, modules, dashboard, weightUnit, energyUnit, waterQuick,
                          aiConsent, cycleConsent, lockSensitive, automations, health, activeEnergy, rest,
                          autoRest, activeGym, cycleLength, periodLength, waterReminder, weighReminder,
                          mealReminder, appleUser, backend]
    }
}
