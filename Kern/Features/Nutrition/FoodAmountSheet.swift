import SwiftUI
import SwiftData

/// Mengenauswahl für ein Lebensmittel mit Live-Vorschau der Nährwerte.
struct FoodAmountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    let food: FoodItem
    let day: Date
    var source: EntrySource
    var originNote: String?
    var onLogged: ((FoodLogEntry) -> Void)?

    @State private var meal: MealType
    @State private var servingID: UUID?
    @State private var quantity: Double
    @State private var countsAsWater = true
    @State private var showsDetails = false

    init(food: FoodItem, meal: MealType, day: Date, source: EntrySource = .search,
         originNote: String? = nil, onLogged: ((FoodLogEntry) -> Void)? = nil) {
        self.food = food
        self.day = day
        self.source = source
        self.originNote = originNote
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
        let first = food.servings.first
        _servingID = State(initialValue: first?.id)
        _quantity = State(initialValue: first == nil ? 100 : 1)
    }

    private var serving: ServingSize? {
        guard let servingID else { return nil }
        return food.servings.first { $0.id == servingID }
    }

    private var grams: Double {
        if let serving { return serving.grams * quantity }
        return quantity
    }

    private var nutrients: Nutrients { food.per100.forGrams(grams) }

    private var amountLabel: String {
        let unit = food.unitSymbol
        if let serving {
            let prefix = quantity == 1 ? "" : "\(Fmt.decimal(quantity, maxDigits: 2)) × "
            return "\(prefix)\(serving.label) (\(Fmt.number(grams)) \(unit))"
        }
        return "\(Fmt.number(grams)) \(unit)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    summary
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }

                Section("Menge") {
                    Picker("Einheit", selection: $servingID) {
                        ForEach(food.servings) { s in
                            Text("\(s.label) · \(Fmt.number(s.grams)) \(food.unitSymbol)").tag(Optional(s.id))
                        }
                        Text(food.isLiquid ? "Milliliter" : "Gramm").tag(UUID?.none)
                    }
                    HStack {
                        Text(serving == nil ? "Menge" : "Anzahl")
                        Spacer()
                        TextField("Menge", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 90)
                        Text(serving == nil ? food.unitSymbol : "×")
                            .foregroundStyle(.secondary)
                        Stepper("Menge anpassen", value: $quantity, in: 0...5000, step: serving == nil ? 10 : 0.5)
                            .labelsHidden()
                    }
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(MealType.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    if food.isLiquid {
                        Toggle("Zur Flüssigkeit zählen", isOn: $countsAsWater)
                    }
                }

                Section {
                    DisclosureGroup("Alle Nährwerte", isExpanded: $showsDetails) {
                        FoodNutrientTable(nutrients: nutrients)
                    }
                } footer: {
                    Text("Werte für \(amountLabel). Basis: pro 100 \(food.unitSymbol).")
                }

                Section("Herkunft") {
                    HStack {
                        QualityBadge(quality: food.quality)
                        Spacer()
                        Text(food.source.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let originNote {
                        Text(originNote).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let license = food.licenseNote ?? food.source.licenseNote {
                        Text(license).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !food.per100.isPlausible {
                        InfoNote(text: "Die Energieangabe passt nicht ganz zu den Makronährstoffen. Bitte prüfe die Werte auf der Verpackung.",
                                 symbol: "exclamationmark.triangle", tint: Theme.warning)
                    }
                    if food.quality == .aiUnconfirmed {
                        InfoNote(text: "KI-Schätzung – keine gemessenen Nährwerte.", symbol: "sparkles", tint: Theme.warning)
                    }
                }
            }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        food.isFavorite.toggle()
                        context.saveQuietly()
                    } label: {
                        Image(systemName: food.isFavorite ? "star.fill" : "star")
                    }
                    .accessibilityLabel(food.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
                    .sensoryFeedback(.selection, trigger: food.isFavorite)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Hinzufügen · \(Fmt.energyWithUnit(nutrients.kcal, unit: prefs.energyUnit))",
                                    isEnabled: grams > 0) {
                    log()
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, Theme.Space.xs)
            }
            .onChange(of: servingID) { oldValue, newValue in
                // Beim Wechsel der Einheit die Menge sinnvoll umrechnen.
                let oldGrams = oldValue.flatMap { id in food.servings.first { $0.id == id }?.grams }
                let currentGrams = (oldGrams ?? 1) * quantity
                if let newID = newValue, let s = food.servings.first(where: { $0.id == newID }) {
                    quantity = max((currentGrams / s.grams).rounded(toNearest: 0.5), 0.5)
                } else {
                    quantity = currentGrams.rounded()
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let brand = food.brand, !brand.isEmpty {
                Text(brand).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.energy(nutrients.kcal, unit: prefs.energyUnit))
                    .font(.metricMedium)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(prefs.energyUnit.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(amountLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: Theme.Space.m) {
                FoodMacroValue(label: "Protein", grams: nutrients.protein, tint: Theme.protein)
                FoodMacroValue(label: "Kohlenhydrate", grams: nutrients.carbs, tint: Theme.carbs)
                FoodMacroValue(label: "Fett", grams: nutrients.fat, tint: Theme.fat)
            }
        }
        .animation(.smooth, value: grams)
    }

    private func log() {
        let entry = LogService.logFood(food, grams: grams, amountLabel: amountLabel, meal: meal,
                                       date: day.withCurrentTime(), source: source,
                                       countsAsWater: countsAsWater, in: context)
        onLogged?(entry)
        dismiss()
    }
}

/// Kompakte Makro-Kennzahl mit Farbmarke.
struct FoodMacroValue: View {
    let label: String
    let grams: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Fmt.decimal(grams)) g")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Vollständige Nährwerttabelle (nur bekannte Werte; fehlende als „–“).
struct FoodNutrientTable: View {
    let nutrients: Nutrients

    var body: some View {
        VStack(spacing: 8) {
            row("Energie", "\(Fmt.number(nutrients.kcal)) kcal · \(Fmt.number(nutrients.kcal * 4.184)) kJ")
            row("Fett", grams(nutrients.fat))
            row("davon gesättigte Fettsäuren", grams(nutrients.saturatedFat), indent: true)
            row("Kohlenhydrate", grams(nutrients.carbs))
            row("davon Zucker", grams(nutrients.sugar), indent: true)
            row("Ballaststoffe", grams(nutrients.fiber))
            row("Protein", grams(nutrients.protein))
            row("Salz", grams(nutrients.salt, digits: 2))
            ForEach(nutrients.micronutrientRows, id: \.label) { micro in
                row(micro.label, "\(Fmt.decimal(micro.value, maxDigits: 1)) \(micro.unit)")
            }
        }
        .padding(.vertical, 4)
    }

    private func grams(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "–" }
        return "\(Fmt.decimal(value, maxDigits: digits)) g"
    }

    private func row(_ title: String, _ value: String, indent: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(indent ? .footnote : .subheadline)
                .foregroundStyle(indent ? .secondary : .primary)
                .padding(.leading, indent ? 12 : 0)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
