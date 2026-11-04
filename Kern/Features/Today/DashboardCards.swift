import SwiftUI
import SwiftData

// MARK: - Kalorienbudget

struct CalorieBudgetCard: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router
    @Environment(HealthKitManager.self) private var health
    let profile: UserProfile
    let totals: Nutrients

    private var activeBonus: Double {
        guard prefs.healthKitEnabled, prefs.addActiveEnergyToBudget else { return 0 }
        return health.todayActiveEnergyKcal ?? 0
    }

    private var budget: Double { Double(profile.calorieTarget) + activeBonus }
    private var remaining: Double { budget - totals.kcal }

    var body: some View {
        Button {
            router.show(tab: .nutrition)
        } label: {
            Card {
                CardHeader(title: profile.wantsCalorieTarget ? "Kalorienbudget" : "Energie heute", symbol: "flame", tint: Theme.accent) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                if profile.wantsCalorieTarget {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.energy(abs(remaining), unit: prefs.energyUnit))
                            .font(.metricLarge)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: remaining))
                            .foregroundStyle(remaining < 0 ? Theme.warning : .primary)
                        Text(remaining < 0 ? "\(prefs.energyUnit.symbol) über Ziel" : "\(prefs.energyUnit.symbol) übrig")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    LinearMeter(progress: budget > 0 ? totals.kcal / budget : 0, tint: Theme.accent, height: 8)

                    HStack(spacing: Theme.Space.l) {
                        StatValue(value: Fmt.energy(budget, unit: prefs.energyUnit), label: "Ziel", valueFont: .subheadline.weight(.semibold))
                        StatValue(value: Fmt.energy(totals.kcal, unit: prefs.energyUnit), label: "Gegessen", valueFont: .subheadline.weight(.semibold))
                        if activeBonus > 0 {
                            StatValue(value: "+\(Fmt.energy(activeBonus, unit: prefs.energyUnit))", label: "Aktivität", valueFont: .subheadline.weight(.semibold))
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.energy(totals.kcal, unit: prefs.energyUnit))
                            .font(.metricLarge)
                            .monospacedDigit()
                        Text(prefs.energyUnit.symbol).font(.body.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet das Ernährungstagebuch")
    }
}

// MARK: - Makros

struct MacrosCard: View {
    let profile: UserProfile
    let totals: Nutrients

    var body: some View {
        Card {
            CardHeader(title: "Makronährstoffe", symbol: "chart.bar")
            MetricRow(label: "Protein", value: totals.protein, target: Double(profile.proteinTargetG), tint: Theme.protein)
            MetricRow(label: "Kohlenhydrate", value: totals.carbs, target: Double(profile.carbTargetG), tint: Theme.carbs)
            MetricRow(label: "Fett", value: totals.fat, target: Double(profile.fatTargetG), tint: Theme.fat)
            if let fiber = totals.fiber {
                MetricRow(label: "Ballaststoffe", value: fiber, target: Double(profile.fiberTargetG), tint: Theme.fiber)
            }
        }
    }
}

// MARK: - Wasser

struct WaterCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    let profile: UserProfile
    let totalMl: Double
    @State private var lastAdded = 0

    var body: some View {
        Card {
            NavigationLink(value: AppDestination.water) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    CardHeader(title: "Wasser", symbol: "drop.fill", tint: Theme.water) {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.decimal(totalMl / 1000, maxDigits: 2))
                            .font(.metricMedium)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: totalMl))
                        Text("/ \(Fmt.decimal(Double(profile.waterTargetMl) / 1000, maxDigits: 2)) l")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    LinearMeter(progress: Double(totalMl) / Double(max(profile.waterTargetMl, 1)), tint: Theme.water, height: 8, showsOverflow: false)
                }
            }
            .buttonStyle(.plain)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(prefs.waterQuickAmounts.prefix(3), id: \.self) { ml in
                        Button {
                            LogService.logWater(ml: Double(ml), in: context)
                            lastAdded += 1
                        } label: {
                            Text("+\(ml) ml")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(Theme.water)
                    }
                }
            }
            .sensoryFeedback(.increase, trigger: lastAdded)
        }
    }
}

// MARK: - Aktivität

struct ActivityCard: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(HealthKitManager.self) private var health
    let profile: UserProfile

    var body: some View {
        Card {
            CardHeader(title: "Aktivität", symbol: "figure.walk", tint: Theme.positive)
            if prefs.healthKitEnabled {
                let steps = health.todaySteps ?? 0
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    RingMeter(progress: steps / Double(max(profile.stepsTarget, 1)), tint: Theme.positive, lineWidth: 7)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Fmt.number(steps)).font(.metricMedium).monospacedDigit()
                            Text("Schritte").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        Text("Ziel \(Fmt.number(Double(profile.stepsTarget)))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let active = health.todayActiveEnergyKcal {
                        StatValue(value: Fmt.energy(active, unit: prefs.energyUnit), unit: prefs.energyUnit.symbol, label: "Aktiv")
                    }
                }
                if !prefs.addActiveEnergyToBudget {
                    Text("Aktivitätskalorien werden nicht zusätzlich zum Budget gezählt, da dein Aktivitätsfaktor sie bereits berücksichtigt. Änderbar in den Einstellungen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                NavigationLink(value: AppDestination.settingsSection(.health)) {
                    HStack {
                        RowLabel(title: "Apple Health verbinden", subtitle: "Schritte und Aktivität automatisch übernehmen",
                                 symbol: "heart", tint: Theme.fat)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Gewohnheiten

struct HabitsCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.order) private var habits: [Habit]
    @Query private var checks: [HabitCheck]

    init() {
        let key = DayKey.today
        _checks = Query(filter: #Predicate<HabitCheck> { $0.dayKey == key })
    }

    var body: some View {
        Card {
            CardHeader(title: "Gewohnheiten", symbol: "checkmark.circle", tint: Theme.positive) {
                NavigationLink(value: AppDestination.habits) {
                    Text(habits.isEmpty ? "Anlegen" : "\(doneCount)/\(habits.count)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                }
            }
            if habits.isEmpty {
                Text("Lege eigene tägliche Gewohnheiten an, z. B. „10 Minuten Mobility“ oder „Gemüse zu jeder Mahlzeit“.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(habits.prefix(5)) { habit in
                    HabitToggleRow(habit: habit, isDone: isDone(habit)) { toggle(habit) }
                }
            }
        }
    }

    private var doneCount: Int { habits.filter(isDone).count }

    private func isDone(_ habit: Habit) -> Bool { checks.contains { $0.habitID == habit.id } }

    private func toggle(_ habit: Habit) {
        HabitStore.toggle(habit, on: .now, checks: checks, in: context)
    }
}

/// Zeile mit Abhak-Kreis für eine Gewohnheit.
struct HabitToggleRow: View {
    let habit: Habit
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Theme.positive : Color(uiColor: .tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: habit.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(habit.name)
                    .font(.body)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isDone) { _, new in new }
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

// MARK: - Konstanz

/// Zeigt, an welchen der letzten 28 Tage Ernährung erfasst wurde.
struct ConsistencyCard: View {
    @Query private var entries: [FoodLogEntry]
    private let days = 28

    init() {
        let start = Date.now.adding(days: -27).startOfDay
        _entries = Query(filter: #Predicate<FoodLogEntry> { $0.date >= start })
    }

    private var kcalByDay: [String: Double] {
        Dictionary(grouping: entries, by: \.dayKey).mapValues { $0.reduce(0) { $0 + $1.nutrients.kcal } }
    }

    var body: some View {
        let keys = DayKey.range(count: days)
        let map = kcalByDay
        let logged = keys.filter { (map[$0] ?? 0) > 0 }.count
        Card {
            CardHeader(title: "Konstanz", symbol: "square.grid.3x3.fill", tint: Theme.accent) {
                Text("\(logged) von \(days) Tagen")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    let kcal = map[key] ?? 0
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(kcal > 0 ? Theme.accent.opacity(kcal >= 1000 ? 1 : 0.45) : Theme.fill)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if key == DayKey.today {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
                            }
                        }
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("An \(logged) von \(days) Tagen Ernährung erfasst")
            Text("Kräftig = vollständig erfasst (ab 1’000 kcal), hell = teilweise.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
