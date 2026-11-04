import SwiftUI
import SwiftData
import Charts

private let nutritionBeveragePresets: [(name: String, symbol: String)] = [
    ("Wasser", "drop"), ("Mineralwasser", "bubbles.and.sparkles"), ("Tee", "cup.and.saucer"),
    ("Kaffee", "mug"), ("Saft", "takeoutbag.and.cup.and.straw")
]

// MARK: - Wasser-Übersicht

/// Flüssigkeitsaufnahme: Tagesfortschritt, Schnellerfassung, Verlauf und Wochenübersicht.
struct WaterView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    @Query private var profiles: [UserProfile]
    @Query private var recent: [WaterEntry]

    @State private var customAmount: Double = 200
    @State private var beverage = "Wasser"
    @State private var customBeverage = ""
    @State private var showsCustomBeverage = false
    @State private var logCount = 0
    @State private var editsQuickAmounts = false

    init() {
        let start = Date.now.adding(days: -6).startOfDay
        _recent = Query(filter: #Predicate<WaterEntry> { $0.date >= start }, sort: \WaterEntry.date, order: .reverse)
    }

    private var todayKey: String { DayKey.today }
    private var today: [WaterEntry] { recent.filter { $0.dayKey == todayKey } }
    private var todayTotal: Double { today.reduce(0) { $0 + $1.ml } }
    private var target: Double { Double(profiles.first?.waterTargetMl ?? 2500) }

    private var week: [(date: Date, ml: Double)] {
        DayKey.range(count: 7).compactMap { key in
            guard let date = DayKey.date(from: key) else { return nil }
            let ml = recent.filter { $0.dayKey == key }.reduce(0) { $0 + $1.ml }
            return (date, ml)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                progressCard
                quickCard
                weekCard
                entriesCard
                InfoNote(text: "Getränke mit Nährwerten (z. B. Milch oder Saft) erfasst du im Ernährungstagebuch. Mit „Zur Flüssigkeit zählen“ erscheinen sie automatisch hier – ohne doppelte Erfassung.")
                Button {
                    router.present(.foodSearch(meal: MealType.suggested(), day: .now))
                } label: {
                    Label("Getränk mit Nährwerten erfassen", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .navigationTitle("Wasser")
        .sensoryFeedback(.increase, trigger: logCount)
        .sheet(isPresented: $editsQuickAmounts) {
            NutritionQuickAmountsEditor()
                .presentationDetents([.medium])
        }
        .alert("Eigenes Getränk", isPresented: $showsCustomBeverage) {
            TextField("Name", text: $customBeverage)
            Button("Übernehmen") {
                let name = customBeverage.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { beverage = name }
                customBeverage = ""
            }
            Button("Abbrechen", role: .cancel) { customBeverage = "" }
        }
    }

    // MARK: Karten

    private var progressCard: some View {
        Card {
            CardHeader(title: "Heute", symbol: "drop.fill", tint: Theme.water)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.decimal(todayTotal / 1000, maxDigits: 2))
                    .font(.metricLarge)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("von \(Fmt.decimal(target / 1000, maxDigits: 2)) l")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.percent(target > 0 ? todayTotal / target : 0))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.water)
            }
            LinearMeter(progress: target > 0 ? todayTotal / target : 0, tint: Theme.water, height: 8, showsOverflow: false)
            if todayTotal >= target {
                Text("Trinkziel erreicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Noch \(Fmt.volume(target - todayTotal)) bis zum Ziel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickCard: some View {
        Card {
            CardHeader(title: "Erfassen", symbol: "plus") {
                Button("Mengen anpassen") { editsQuickAmounts = true }
                    .font(.footnote)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(nutritionBeveragePresets, id: \.name) { preset in
                        ChoiceChip(title: preset.name, symbol: preset.symbol, isSelected: beverage == preset.name) {
                            beverage = preset.name
                        }
                    }
                    if !nutritionBeveragePresets.contains(where: { $0.name == beverage }) {
                        ChoiceChip(title: beverage, symbol: "cup.and.heat.waves", isSelected: true) {}
                    }
                    ChoiceChip(title: "Andere …", symbol: "plus", isSelected: false) {
                        showsCustomBeverage = true
                    }
                }
            }
            .scrollClipDisabled()

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(prefs.waterQuickAmounts, id: \.self) { amount in
                        Button {
                            log(Double(amount))
                        } label: {
                            VStack(spacing: 2) {
                                Text(Fmt.number(Double(amount)))
                                    .font(.headline.monospacedDigit())
                                Text("ml").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .accessibilityLabel("\(amount) Milliliter \(beverage) hinzufügen")
                    }
                }
            }

            HStack {
                Stepper(value: $customAmount, in: 50...2000, step: 50) {
                    Text("\(Fmt.number(customAmount)) ml")
                        .font(.body.monospacedDigit())
                }
                Button("Hinzufügen") { log(customAmount) }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var weekCard: some View {
        Card {
            CardHeader(title: "Letzte 7 Tage", symbol: "chart.bar", tint: Theme.water)
            Chart {
                ForEach(week, id: \.date) { day in
                    BarMark(x: .value("Tag", day.date, unit: .day), y: .value("Menge", day.ml / 1000))
                        .foregroundStyle(Theme.water)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Ziel", target / 1000))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Ziel").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow).locale(Fmt.locale))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Fmt.decimal(v, maxDigits: 1)) l") }
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Wasseraufnahme der letzten 7 Tage")
            .accessibilityValue(week.map { "\(Fmt.shortDate($0.date)): \(Fmt.volume($0.ml))" }.joined(separator: ", "))
            let average = week.reduce(0) { $0 + $1.ml } / Double(max(week.count, 1))
            Text("Durchschnitt \(Fmt.volume(average)) pro Tag")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var entriesCard: some View {
        Card {
            CardHeader(title: "Einträge heute", symbol: "list.bullet")
            if today.isEmpty {
                Text("Noch nichts erfasst.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(today) { entry in
                        HStack(spacing: Theme.Space.s) {
                            Text(Fmt.time(entry.date))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.beverage)
                                if entry.linkedFoodEntryID != nil {
                                    Text("aus dem Ernährungstagebuch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Fmt.volume(entry.ml))
                                .font(.subheadline.monospacedDigit())
                            Button {
                                delete(entry)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.beverage) \(Fmt.volume(entry.ml)) entfernen")
                        }
                        .padding(.vertical, 6)
                        if entry.id != today.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: Aktionen

    private func log(_ ml: Double) {
        withAnimation(.smooth) {
            _ = LogService.logWater(ml: ml, beverage: beverage, in: context)
        }
        logCount += 1
    }

    private func delete(_ entry: WaterEntry) {
        AuditLog.record(context, actor: .user, summary: "\(Fmt.volume(entry.ml)) \(entry.beverage) entfernt",
                        entityType: EntityType.water, entityID: entry.id.uuidString)
        // Verknüpfter Ernährungseintrag bleibt bestehen, zählt aber nicht mehr zur Flüssigkeit.
        if let foodID = entry.linkedFoodEntryID {
            let linked = (try? context.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.id == foodID }))) ?? []
            linked.forEach { $0.linkedWaterEntryID = nil }
        }
        withAnimation { context.delete(entry) }
        context.saveQuietly()
        WidgetBridge.refresh(context: context)
    }
}

// MARK: - Schnellmengen bearbeiten

private struct NutritionQuickAmountsEditor: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var amounts: [Double] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(amounts.indices, id: \.self) { index in
                        Stepper(value: $amounts[index], in: 50...1500, step: 10) {
                            Text("\(Fmt.number(amounts[index])) ml").monospacedDigit()
                        }
                    }
                } footer: {
                    Text("Diese Mengen erscheinen als Schnelltasten für Wasser und im Widget.")
                }
            }
            .navigationTitle("Schnellmengen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        prefs.waterQuickAmounts = amounts.map { Int($0) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                amounts = prefs.waterQuickAmounts.map(Double.init)
                while amounts.count < 3 { amounts.append(250) }
            }
        }
    }
}

// MARK: - Schnell-Sheet

/// Kompakte Wassererfassung (z. B. aus Schnellaktionen und Deep Links).
struct WaterQuickSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @Query private var today: [WaterEntry]
    @Query private var profiles: [UserProfile]

    @State private var customAmount: Double = 200
    @State private var logCount = 0

    init() {
        let key = DayKey.today
        _today = Query(filter: #Predicate<WaterEntry> { $0.dayKey == key })
    }

    private var total: Double { today.reduce(0) { $0 + $1.ml } }
    private var target: Double { Double(profiles.first?.waterTargetMl ?? 2500) }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.l) {
                VStack(spacing: Theme.Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.volume(total))
                            .font(.metricMedium)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("von \(Fmt.volume(target))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    LinearMeter(progress: target > 0 ? total / target : 0, tint: Theme.water, height: 8, showsOverflow: false)
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(prefs.waterQuickAmounts, id: \.self) { amount in
                            Button {
                                log(Double(amount))
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "drop.fill")
                                        .font(.title3)
                                        .foregroundStyle(Theme.water)
                                    Text(Fmt.number(Double(amount)))
                                        .font(.title3.weight(.semibold).monospacedDigit())
                                    Text("ml")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                            .accessibilityLabel("\(amount) Milliliter Wasser hinzufügen")
                        }
                    }
                }

                HStack {
                    Stepper(value: $customAmount, in: 50...2000, step: 50) {
                        Text("\(Fmt.number(customAmount)) ml")
                            .font(.body.monospacedDigit())
                    }
                    Button("Hinzufügen") { log(customAmount) }
                        .buttonStyle(.glassProminent)
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.screenPadding)
            .navigationTitle("Wasser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sensoryFeedback(.increase, trigger: logCount)
        }
    }

    private func log(_ ml: Double) {
        withAnimation(.smooth) {
            _ = LogService.logWater(ml: ml, in: context)
        }
        logCount += 1
    }
}
