import SwiftUI
import SwiftData

// MARK: - Schnelleintrag

/// Schnelleintrag nur mit Kalorien (Makros optional).
struct NutritionQuickEntrySheet: View {
    let day: Date
    var onLogged: ((String) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @State private var meal: MealType
    @State private var name = ""
    @State private var energy: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    init(meal: MealType, day: Date, onLogged: ((String) -> Void)? = nil) {
        self.day = day
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
    }

    private var kcal: Double {
        guard let energy else { return 0 }
        return prefs.energyUnit == .kJ ? energy / 4.184 : energy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung (optional)", text: $name)
                    NumberField(title: "Energie", value: $energy, unit: prefs.energyUnit.symbol, fractionDigits: 0)
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Makronährstoffe (optional)") {
                    NumberField(title: "Protein", value: $protein, unit: "g")
                    NumberField(title: "Kohlenhydrate", value: $carbs, unit: "g")
                    NumberField(title: "Fett", value: $fat, unit: "g")
                }
            }
            .navigationTitle("Schnelleintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { save() }
                        .disabled(kcal <= 0 && (protein ?? 0) + (carbs ?? 0) + (fat ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        var total = kcal
        if total <= 0 {
            total = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
        }
        let nutrients = Nutrients(kcal: total, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Schnelleintrag" : name
        LogService.logCustom(name: title, nutrients: nutrients, grams: 100, amountLabel: "Schnelleintrag",
                             meal: meal, date: day.withCurrentTime(), quality: .community, source: .quickAdd,
                             isEstimate: false, in: context)
        onLogged?(title)
        dismiss()
    }
}

// MARK: - Eigenes Lebensmittel

/// Editor für eigene Lebensmittel (Nährwerte pro 100 g bzw. 100 ml).
struct NutritionCustomFoodEditor: View {
    var barcode: String?
    var onSaved: ((FoodItem) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand = ""
    @State private var code: String
    @State private var isLiquid = false
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var sugar: Double?
    @State private var fat: Double?
    @State private var saturated: Double?
    @State private var fiber: Double?
    @State private var salt: Double?
    @State private var servings: [ServingSize] = []
    @State private var newServingLabel = ""
    @State private var newServingGrams: Double?

    init(barcode: String?, initialName: String = "", onSaved: ((FoodItem) -> Void)? = nil) {
        self.barcode = barcode
        self.onSaved = onSaved
        _name = State(initialValue: initialName)
        _code = State(initialValue: barcode ?? "")
    }

    private var unit: String { isLiquid ? "ml" : "g" }

    private var nutrients: Nutrients {
        Nutrients(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0,
                  sugar: sugar, saturatedFat: saturated, fiber: fiber, salt: salt)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kcal ?? 0) >= 0 && kcal != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Marke (optional)", text: $brand)
                    TextField("Barcode (optional)", text: $code)
                        .keyboardType(.numberPad)
                    Toggle("Getränk (Angaben pro 100 ml)", isOn: $isLiquid)
                }

                Section {
                    NumberField(title: "Energie", value: $kcal, unit: "kcal", fractionDigits: 0)
                    NumberField(title: "Fett", value: $fat, unit: "g")
                    NumberField(title: "davon gesättigt", value: $saturated, unit: "g")
                    NumberField(title: "Kohlenhydrate", value: $carbs, unit: "g")
                    NumberField(title: "davon Zucker", value: $sugar, unit: "g")
                    NumberField(title: "Ballaststoffe", value: $fiber, unit: "g")
                    NumberField(title: "Protein", value: $protein, unit: "g")
                    NumberField(title: "Salz", value: $salt, unit: "g", fractionDigits: 2)
                } header: {
                    Text("Nährwerte pro 100 \(unit)")
                } footer: {
                    if kcal != nil && !nutrients.isPlausible {
                        Text("Die Energie passt nicht ganz zu den Makronährstoffen. Bitte prüfe die Angaben auf der Verpackung.")
                            .foregroundStyle(Theme.warning)
                    }
                }

                Section("Portionen") {
                    ForEach(servings) { s in
                        LabeledContent(s.label, value: "\(Fmt.number(s.grams)) \(unit)")
                    }
                    .onDelete { servings.remove(atOffsets: $0) }
                    HStack {
                        TextField("z. B. 1 Becher", text: $newServingLabel)
                        TextField(unit, value: $newServingGrams, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                        Text(unit).foregroundStyle(.secondary)
                        Button {
                            addServing()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(newServingLabel.isEmpty || (newServingGrams ?? 0) <= 0)
                        .accessibilityLabel("Portion hinzufügen")
                    }
                }

                Section {
                    InfoNote(text: "Eigene Lebensmittel bleiben privat auf deinem Gerät. Nicht bekannte Werte leer lassen – sie werden nicht als 0 gezählt.")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Eigenes Lebensmittel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func addServing() {
        guard let grams = newServingGrams, grams > 0, !newServingLabel.isEmpty else { return }
        servings.append(ServingSize(label: newServingLabel, grams: grams))
        newServingLabel = ""
        newServingGrams = nil
    }

    private func save() {
        addServing()
        let cleanCode = code.filter(\.isNumber)
        let quality: DataQuality = nutrients.isIncomplete ? .incomplete : .community
        let item = FoodItem(name: name.trimmingCharacters(in: .whitespaces),
                            brand: brand.isEmpty ? nil : brand,
                            barcode: cleanCode.isEmpty ? nil : cleanCode,
                            category: "Eigene", source: .user, quality: quality,
                            per100: nutrients, servings: servings, isLiquid: isLiquid)
        context.insert(item)
        AuditLog.record(context, actor: .user, summary: "Eigenes Lebensmittel „\(item.name)“ angelegt",
                        entityType: "FoodItem", entityID: item.id.uuidString)
        context.saveQuietly()
        onSaved?(item)
        dismiss()
    }
}
