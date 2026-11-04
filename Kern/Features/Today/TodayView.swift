import SwiftUI
import SwiftData

/// Personalisiertes Dashboard. Karten richten sich nach Ziel und aktiven Modulen
/// und können vom Nutzer frei angeordnet werden.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dayKey = DayKey.today

    var body: some View {
        TodayContent(dayKey: dayKey)
            .id(dayKey)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { dayKey = DayKey.today }
            }
    }
}

private struct TodayContent: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]
    @Query private var entries: [FoodLogEntry]
    @Query private var water: [WaterEntry]

    @AppStorage("kern.today.firstSteps.dismissed") private var firstStepsDismissed = false

    init(dayKey: String) {
        _entries = Query(filter: #Predicate<FoodLogEntry> { $0.dayKey == dayKey }, sort: \FoodLogEntry.date)
        _water = Query(filter: #Predicate<WaterEntry> { $0.dayKey == dayKey }, sort: \WaterEntry.date)
    }

    private var profile: UserProfile? { profiles.first }
    private var totals: Nutrients { entries.reduce(Nutrients.zero) { $0 + $1.nutrients } }
    private var waterTotal: Double { water.reduce(0) { $0 + $1.ml } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                header

                if !firstStepsDismissed && entries.isEmpty {
                    FirstStepsCard { withAnimation(.smooth) { firstStepsDismissed = true } }
                }

                ForEach(prefs.visibleDashboardCards) { kind in
                    card(for: kind)
                        .transition(.opacity)
                }

                AreasSection()
                    .padding(.top, Theme.Space.s)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.Space.xxl)
            .animation(.smooth, value: prefs.dashboardCards)
        }
        .screenBackground()
        .navigationTitle("Heute")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.dashboardEditor)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Startseite anpassen")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppDestination.settings) {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profil und Einstellungen")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Fmt.locale)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, Theme.Space.xxs)
        .padding(.bottom, Theme.Space.xxs)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base: String = switch hour {
        case 5..<11: "Guten Morgen"
        case 11..<17: "Guten Tag"
        case 17..<23: "Guten Abend"
        default: "Hallo"
        }
        if let name = profile?.firstName, !name.isEmpty { return "\(base), \(name)" }
        return base
    }

    @ViewBuilder
    private func card(for kind: DashboardCardKind) -> some View {
        switch kind {
        case .calorieBudget:
            if let profile { CalorieBudgetCard(profile: profile, totals: totals) }
        case .macros:
            if let profile { MacrosCard(profile: profile, totals: totals) }
        case .water:
            if let profile { WaterCard(profile: profile, totalMl: waterTotal) }
        case .weightTrend: WeightTrendCard()
        case .nextWorkout: NextWorkoutCard()
        case .trainingWeek: TrainingWeekCard()
        case .strength: StrengthCard()
        case .activity:
            if let profile { ActivityCard(profile: profile) }
        case .supplements: SupplementsTodayCard()
        case .habits: HabitsCard()
        case .cycle: CycleTodayCard()
        case .weeklyInsight: WeeklyInsightCard()
        case .consistency: ConsistencyCard()
        case .measurements: MeasurementsCard()
        }
    }
}

// MARK: - Erste Schritte

private struct FirstStepsCard: View {
    @Environment(AppRouter.self) private var router
    let onDismiss: () -> Void

    var body: some View {
        Card {
            CardHeader(title: "Erste Schritte", symbol: "sparkle", tint: Theme.accent) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ausblenden")
            }
            VStack(spacing: Theme.Space.xs) {
                step("Erste Mahlzeit erfassen", symbol: "fork.knife") {
                    router.present(.foodSearch(meal: .suggested(), day: .now))
                }
                Divider().padding(.leading, 44)
                step("Coach ausprobieren", symbol: "bubble.left.and.text.bubble.right") {
                    router.present(.coach(prefill: nil))
                }
                Divider().padding(.leading, 44)
                step("Trainingsplan erstellen", symbol: "dumbbell") {
                    router.open(.planGenerator)
                }
            }
        }
    }

    private func step(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                RowLabel(title: title, symbol: symbol)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bereiche

/// Kontextabhängiger Zugang zu weiteren Modulen.
private struct AreasSection: View {
    @Environment(AppPreferences.self) private var prefs

    private var items: [(AppDestination, String, String, Color)] {
        var result: [(AppDestination, String, String, Color)] = []
        if prefs.isEnabled(.supplements) { result.append((.supplements, "Supplements", "pills", Theme.supplement)) }
        if prefs.isEnabled(.cycle) { result.append((.cycle, "Zyklus", "circle.dashed", Theme.cycle)) }
        if prefs.isEnabled(.habits) { result.append((.habits, "Gewohnheiten", "checkmark.circle", Theme.positive)) }
        if prefs.isEnabled(.water) { result.append((.water, "Wasser", "drop", Theme.water)) }
        result.append((.weeklyReport, "Wochenanalyse", "text.magnifyingglass", Theme.weight))
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionTitle(title: "Bereiche")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    NavigationLink(value: item.0) {
                        HStack {
                            RowLabel(title: item.1, symbol: item.2, tint: item.3)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}
