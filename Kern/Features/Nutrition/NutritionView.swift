import SwiftUI
import SwiftData

/// Ernährungstagebuch: Tagesübersicht, Mahlzeiten, Makros und Wasser.
struct NutritionView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NutritionDayList(day: router.nutritionDay)
            .navigationTitle("Ernährung")
    }
}

// MARK: - Tagesliste

private struct NutritionDayList: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs
    @Environment(HealthKitManager.self) private var health

    @Query private var entries: [FoodLogEntry]
    @Query private var water: [WaterEntry]
    @Query private var profiles: [UserProfile]

    @State private var editingEntry: FoodLogEntry?
    @State private var showsDatePicker = false
    @State private var showsCopyDay = false
    @State private var saveMealSource: MealType?
    @State private var savedMealName = ""
    @State private var showsMicros = false
    @State private var confirmation: String?

    init(day: Date) {
        self.day = day
        let key = DayKey.make(day)
        _entries = Query(filter: #Predicate<FoodLogEntry> { $0.dayKey == key }, sort: \FoodLogEntry.date)
        _water = Query(filter: #Predicate<WaterEntry> { $0.dayKey == key })
    }

    private var profile: UserProfile? { profiles.first }
    private var totals: Nutrients { entries.reduce(Nutrients.zero) { $0 + $1.nutrients } }
    private var waterTotal: Double { water.reduce(0) { $0 + $1.ml } }

    private var activityBonus: Double {
        guard prefs.addActiveEnergyToBudget, Calendar.current.isDateInToday(day) else { return 0 }
        return health.todayActiveEnergyKcal ?? 0
    }

    private var calorieTarget: Double { Double(profile?.calorieTarget ?? 2000) + activityBonus }

    var body: some View {
        List {
            Section {
                daySwitcher
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section {
                summary
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }

            ForEach(MealType.allCases) { meal in
                mealSection(meal)
            }

            if prefs.isEnabled(.water) {
                Section {
                    NavigationLink(value: AppDestination.water) {
                        HStack(spacing: Theme.Space.s) {
                            RowLabel(title: "Wasser", subtitle: waterSubtitle, symbol: "drop.fill", tint: Theme.water)
                        }
                    }
                }
            }

            Section {
                DisclosureGroup("Details & Mikronährstoffe", isExpanded: $showsMicros) {
                    FoodNutrientTable(nutrients: totals)
                    Text("Summen enthalten nur Werte, die für die jeweiligen Lebensmittel bekannt sind.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if entries.contains(where: \.isEstimate) {
                    InfoNote(text: "Einige Einträge sind KI-Schätzungen und keine gemessenen Nährwerte.",
                             symbol: "sparkles", tint: Theme.warning)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .screenBackground()
        .toolbar { toolbarContent }
        .sheet(item: $editingEntry) { entry in
            NutritionEntryEditor(entry: entry)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsDatePicker) {
            NutritionDatePickerSheet(day: Binding(get: { router.nutritionDay }, set: { router.nutritionDay = $0 }))
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsCopyDay) {
            NutritionCopyDaySheet(targetDay: day)
        }
        .alert("Als Mahlzeit speichern", isPresented: Binding(get: { saveMealSource != nil }, set: { if !$0 { saveMealSource = nil } })) {
            TextField("Name", text: $savedMealName)
            Button("Speichern") { saveMeal() }
            Button("Abbrechen", role: .cancel) { saveMealSource = nil }
        } message: {
            Text("Die Einträge werden als wiederverwendbare Kombination gespeichert.")
        }
        .overlay(alignment: .bottom) {
            if let confirmation {
                NutritionToast(text: confirmation)
                    .padding(.bottom, Theme.Space.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.smooth) { self.confirmation = nil }
                    }
            }
        }
    }

    // MARK: Teile

    private var daySwitcher: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Vorheriger Tag")

                Button { showsDatePicker = true } label: {
                    VStack(spacing: 1) {
                        Text(Fmt.day(day))
                            .font(.headline)
                        let cal = Calendar.current
                        if cal.isDateInToday(day) || cal.isDateInYesterday(day) || cal.isDateInTomorrow(day) {
                            Text(Fmt.mediumDate(day))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Datum auswählen")

                Button { shiftDay(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Nächster Tag")
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: some View {
        let consumed = totals.kcal
        let remaining = calorieTarget - consumed
        let showsTarget = profile?.wantsCalorieTarget ?? true
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(showsTarget ? (remaining >= 0 ? "Verbleibend" : "Über dem Ziel") : "Gegessen")
                        .font(.subheadline)
                        .foregroundStyle(remaining < 0 && showsTarget ? Theme.warning : .secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.energy(showsTarget ? abs(remaining) : consumed, unit: prefs.energyUnit))
                            .font(.metricLarge)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(prefs.energyUnit.symbol)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if showsTarget {
                    VStack(alignment: .trailing, spacing: 6) {
                        summaryPair("Gegessen", Fmt.energy(consumed, unit: prefs.energyUnit))
                        summaryPair("Ziel", Fmt.energy(calorieTarget, unit: prefs.energyUnit))
                    }
                }
            }
            if showsTarget {
                LinearMeter(progress: calorieTarget > 0 ? consumed / calorieTarget : 0, tint: Theme.accent, height: 8)
                if activityBonus > 0 {
                    Text("inkl. \(Fmt.energyWithUnit(activityBonus, unit: prefs.energyUnit)) Aktivität aus Apple Health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: Theme.Space.s) {
                MetricRow(label: "Protein", value: totals.protein, target: Double(profile?.proteinTargetG ?? 0), tint: Theme.protein)
                MetricRow(label: "Kohlenhydrate", value: totals.carbs, target: Double(profile?.carbTargetG ?? 0), tint: Theme.carbs)
                MetricRow(label: "Fett", value: totals.fat, target: Double(profile?.fatTargetG ?? 0), tint: Theme.fat)
            }
            HStack(spacing: 0) {
                smallStat("Ballaststoffe", "\(Fmt.number(totals.fiber ?? 0)) / \(profile?.fiberTargetG ?? 30) g")
                smallStat("Zucker", "\(Fmt.number(totals.sugar ?? 0)) g")
                smallStat("Salz", "\(Fmt.decimal(totals.salt ?? 0, maxDigits: 1)) g")
            }
        }
    }

    private func summaryPair(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func smallStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var waterSubtitle: String {
        let target = Double(profile?.waterTargetMl ?? 2500)
        return "\(Fmt.volume(waterTotal)) von \(Fmt.volume(target))"
    }

    @ViewBuilder
    private func mealSection(_ meal: MealType) -> some View {
        let items = entries.filter { $0.meal == meal }
        let kcal = items.reduce(0) { $0 + $1.nutrients.kcal }
        Section {
            ForEach(items) { entry in
                entryRow(entry)
            }
            if items.isEmpty {
                Button {
                    router.present(.foodSearch(meal: meal, day: day))
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("\(meal.title) erfassen")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: meal.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if kcal > 0 {
                    Text(Fmt.energyWithUnit(kcal, unit: prefs.energyUnit))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !items.isEmpty {
                    Menu {
                        Button("Als Mahlzeit speichern", systemImage: "square.and.arrow.down") {
                            savedMealName = "\(meal.title) \(Fmt.shortDate(day))"
                            saveMealSource = meal
                        }
                        Button("Nochmals hinzufügen (heute)", systemImage: "arrow.counterclockwise") {
                            repeatMeal(items, meal: meal)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Optionen für \(meal.title)")
                }
                Button {
                    router.present(.foodSearch(meal: meal, day: day))
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(meal.title) hinzufügen")
            }
            .textCase(nil)
            .foregroundStyle(Theme.accent)
        }
    }

    private func entryRow(_ entry: FoodLogEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(entry.amountLabel)
                        if entry.isEstimate {
                            Badge(text: "Schätzung", tint: Theme.warning)
                        } else if entry.quality == .incomplete {
                            Badge(text: "Unvollständig", tint: Theme.warning)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Fmt.energy(entry.nutrients.kcal, unit: prefs.energyUnit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation { LogService.deleteFood(entry, in: context) }
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                NutritionMealLogger.copy(entry, to: Date.now, in: context)
                saveAndConfirm("\(entry.name) erneut hinzugefügt")
            } label: {
                Label("Nochmals", systemImage: "arrow.counterclockwise")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            Button("Nochmals hinzufügen", systemImage: "arrow.counterclockwise") {
                NutritionMealLogger.copy(entry, to: Date.now, in: context)
                saveAndConfirm("\(entry.name) erneut hinzugefügt")
            }
            Menu("Verschieben nach") {
                ForEach(MealType.allCases.filter { $0 != entry.meal }) { meal in
                    Button(meal.title) {
                        entry.meal = meal
                        context.saveQuietly()
                    }
                }
            }
            Button("Löschen", systemImage: "trash", role: .destructive) {
                LogService.deleteFood(entry, in: context)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Barcode scannen", systemImage: "barcode.viewfinder") {
                    router.present(.barcode(meal: MealType.suggested(), day: day))
                }
                Button("Foto erkennen", systemImage: "camera") {
                    router.present(.photoFood(meal: MealType.suggested(), day: day))
                }
                Divider()
                Button("Rezepte", systemImage: "book") {
                    router.nutritionPath.append(.recipes)
                }
                Button("Gespeicherte Mahlzeiten", systemImage: "square.stack") {
                    router.nutritionPath.append(.savedMeals)
                }
                Divider()
                Button("Tag kopieren …", systemImage: "doc.on.doc") {
                    showsCopyDay = true
                }
                if !Calendar.current.isDateInToday(day) {
                    Button("Zu heute springen", systemImage: "calendar") {
                        router.nutritionDay = .now
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Weitere Aktionen")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router.present(.foodSearch(meal: MealType.suggested(), day: day))
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Lebensmittel hinzufügen")
        }
    }

    // MARK: Aktionen

    private func shiftDay(_ offset: Int) {
        withAnimation(.snappy) {
            router.nutritionDay = day.adding(days: offset)
        }
    }

    private func saveMeal() {
        guard let meal = saveMealSource else { return }
        let items = entries.filter { $0.meal == meal }.map(NutritionMealLogger.component(from:))
        let name = savedMealName.trimmingCharacters(in: .whitespaces)
        let saved = SavedMeal(name: name.isEmpty ? meal.title : name, meal: meal, items: items)
        context.insert(saved)
        saveMealSource = nil
        saveAndConfirm("Mahlzeit gespeichert")
    }

    private func repeatMeal(_ items: [FoodLogEntry], meal: MealType) {
        for item in items {
            NutritionMealLogger.copy(item, to: Date.now, meal: meal, in: context)
        }
        AuditLog.record(context, actor: .user, summary: "\(meal.title) erneut hinzugefügt (\(items.count) Einträge)",
                        entityType: EntityType.food)
        saveAndConfirm("\(items.count) Einträge hinzugefügt")
    }

    private func saveAndConfirm(_ text: String) {
        context.saveQuietly()
        WidgetBridge.refresh(context: context)
        withAnimation(.smooth) { confirmation = text }
    }
}

// MARK: - Toast

/// Kurze Bestätigung in der Steuerungsebene (Liquid Glass).
struct NutritionToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Datum wählen

private struct NutritionDatePickerSheet: View {
    @Binding var day: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Datum", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Fmt.locale)
                .padding(.horizontal)
                .navigationTitle("Tag wählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Heute") { day = .now }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Eintrag bearbeiten

struct NutritionEntryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    let entry: FoodLogEntry

    @State private var grams: Double
    @State private var meal: MealType
    @State private var note: String
    @State private var confirmsDelete = false

    init(entry: FoodLogEntry) {
        self.entry = entry
        _grams = State(initialValue: entry.grams)
        _meal = State(initialValue: entry.meal)
        _note = State(initialValue: entry.note)
    }

    private var unit: String { entry.isLiquid ? "ml" : "g" }
    private var isPortionBased: Bool { entry.source == .quickAdd }
    private var preview: Nutrients { entry.per100.forGrams(grams) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Fmt.energy(preview.kcal, unit: prefs.energyUnit))
                                .font(.metricMedium)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(prefs.energyUnit.symbol).foregroundStyle(.secondary)
                            Spacer()
                            if entry.isEstimate {
                                QualityBadge(quality: .aiUnconfirmed)
                            } else {
                                QualityBadge(quality: entry.quality)
                            }
                        }
                        HStack(spacing: Theme.Space.m) {
                            FoodMacroValue(label: "Protein", grams: preview.protein, tint: Theme.protein)
                            FoodMacroValue(label: "Kohlenhydrate", grams: preview.carbs, tint: Theme.carbs)
                            FoodMacroValue(label: "Fett", grams: preview.fat, tint: Theme.fat)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if isPortionBased {
                        Stepper(value: Binding(get: { grams / 100 }, set: { grams = max($0, 0.25) * 100 }), in: 0.25...20, step: 0.25) {
                            HStack {
                                Text("Anteil")
                                Spacer()
                                Text("\(Fmt.decimal(grams / 100, maxDigits: 2)) ×").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Text("Menge")
                            Spacer()
                            TextField("Menge", value: $grams, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(maxWidth: 100)
                            Text(unit).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Notiz", text: $note, axis: .vertical)
                } footer: {
                    Text("Erfasst \(Fmt.time(entry.date)) · \(entry.source.title). Die Nährwerte basieren auf dem Stand zum Zeitpunkt des Eintrags.")
                }

                Section {
                    Button("Eintrag löschen", role: .destructive) { confirmsDelete = true }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(grams <= 0)
                }
            }
            .confirmationDialog("Eintrag löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    LogService.deleteFood(entry, in: context)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        var changes: [String] = []
        if abs(grams - entry.grams) > 0.01 {
            changes.append("Menge \(Fmt.number(entry.grams)) → \(Fmt.number(grams)) \(unit)")
            entry.amountLabel = isPortionBased
                ? "\(Fmt.decimal(grams / 100, maxDigits: 2)) × Schnelleintrag"
                : "\(Fmt.number(grams)) \(unit)"
            entry.grams = grams
        }
        if meal != entry.meal {
            changes.append("\(entry.meal.title) → \(meal.title)")
            entry.meal = meal
        }
        entry.note = note
        if !changes.isEmpty {
            AuditLog.record(context, actor: .user, summary: "\(entry.name) geändert", detail: changes.joined(separator: ", "),
                            entityType: EntityType.food, entityID: entry.id.uuidString)
        }
        context.saveQuietly()
        WidgetBridge.refresh(context: context)
        dismiss()
    }
}

// MARK: - Tag kopieren

private struct NutritionCopyDaySheet: View {
    let targetDay: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @State private var sourceDay: Date
    @State private var sourceEntries: [FoodLogEntry] = []
    @State private var selectedMeals: Set<MealType> = Set(MealType.allCases)

    init(targetDay: Date) {
        self.targetDay = targetDay
        _sourceDay = State(initialValue: targetDay.adding(days: -1))
    }

    private var selectedEntries: [FoodLogEntry] {
        sourceEntries.filter { selectedMeals.contains($0.meal) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Von", selection: $sourceDay, displayedComponents: .date)
                        .environment(\.locale, Fmt.locale)
                    LabeledContent("Nach", value: Fmt.day(targetDay))
                }

                Section("Mahlzeiten") {
                    if sourceEntries.isEmpty {
                        Text("An diesem Tag gibt es keine Einträge.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(MealType.allCases) { meal in
                        let items = sourceEntries.filter { $0.meal == meal }
                        if !items.isEmpty {
                            Toggle(isOn: Binding(
                                get: { selectedMeals.contains(meal) },
                                set: { isOn in
                                    if isOn { selectedMeals.insert(meal) } else { selectedMeals.remove(meal) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.title)
                                    Text("\(items.count) Einträge · \(Fmt.energyWithUnit(items.reduce(0) { $0 + $1.nutrients.kcal }, unit: prefs.energyUnit))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tag kopieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "\(selectedEntries.count) Einträge kopieren", isEnabled: !selectedEntries.isEmpty) {
                    copy()
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, Theme.Space.xs)
            }
            .task(id: DayKey.make(sourceDay)) { load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        let key = DayKey.make(sourceDay)
        let descriptor = FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.dayKey == key },
                                                       sortBy: [SortDescriptor(\.date)])
        sourceEntries = (try? context.fetch(descriptor)) ?? []
    }

    private func copy() {
        let items = selectedEntries
        for item in items {
            NutritionMealLogger.copy(item, to: NutritionMealLogger.date(targetDay, keepingTimeOf: item.date), in: context)
        }
        AuditLog.record(context, actor: .user,
                        summary: "\(items.count) Einträge von \(Fmt.shortDate(sourceDay)) nach \(Fmt.shortDate(targetDay)) kopiert",
                        entityType: EntityType.food)
        context.saveQuietly()
        WidgetBridge.refresh(context: context)
        dismiss()
    }
}
