import SwiftUI
import SwiftData

/// Eigene Rezepte: anlegen, bearbeiten, duplizieren und portionsweise erfassen.
struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs

    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]

    @State private var isCreating = false
    @State private var query = ""

    private var filtered: [Recipe] {
        let q = FoodRepository.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return recipes }
        return recipes.filter { FoodRepository.fold($0.name).contains(q) }
    }

    var body: some View {
        List {
            if recipes.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Rezepte", systemImage: "book")
                } description: {
                    Text("Lege eigene Rezepte an. Kern berechnet Kalorien und Nährwerte pro Portion und pro 100 g aus den Zutaten.")
                } actions: {
                    Button("Rezept anlegen") { isCreating = true }
                        .buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { recipe in
                    NavigationLink {
                        NutritionRecipeDetailView(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(recipe.name)
                                if recipe.isFavorite {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.carbs)
                                }
                            }
                            Text("\(recipe.servings) Portionen · \(Fmt.energyWithUnit(recipe.perServing.kcal, unit: prefs.energyUnit)) pro Portion")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { delete(recipe) } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        Button { duplicate(recipe) } label: {
                            Label("Duplizieren", systemImage: "plus.square.on.square")
                        }
                        .tint(Theme.accent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rezepte")
        .searchable(text: $query, prompt: "Rezepte durchsuchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Rezept anlegen")
            }
        }
        .sheet(isPresented: $isCreating) {
            NutritionRecipeEditor(recipe: nil)
        }
    }

    private func delete(_ recipe: Recipe) {
        AuditLog.record(context, actor: .user, summary: "Rezept „\(recipe.name)“ gelöscht", entityType: "Recipe",
                        entityID: recipe.id.uuidString)
        context.delete(recipe)
        context.saveQuietly()
    }

    private func duplicate(_ recipe: Recipe) {
        NutritionRecipeActions.duplicate(recipe, in: context)
    }
}

@MainActor
enum NutritionRecipeActions {
    @discardableResult
    static func duplicate(_ recipe: Recipe, in context: ModelContext) -> Recipe {
        let copy = Recipe(name: "\(recipe.name) (Kopie)", servings: recipe.servings,
                          ingredients: recipe.ingredients.map { var c = $0; c.id = UUID(); return c })
        copy.cookedWeightG = recipe.cookedWeightG
        copy.instructions = recipe.instructions
        context.insert(copy)
        context.saveQuietly()
        return copy
    }
}

// MARK: - Detail

struct NutritionRecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    @State private var isEditing = false
    @State private var isLogging = false
    @State private var confirmsDelete = false

    private var quality: DataQuality { NutritionQuality.worst(recipe.ingredients.map(\.quality)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Card {
                    CardHeader(title: "Pro Portion", symbol: "fork.knife", tint: Theme.accent) {
                        QualityBadge(quality: quality)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.energy(recipe.perServing.kcal, unit: prefs.energyUnit))
                            .font(.metricMedium)
                            .monospacedDigit()
                        Text(prefs.energyUnit.symbol).foregroundStyle(.secondary)
                        Spacer()
                        Text("≈ \(Fmt.number(recipe.servingWeightG)) g")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: Theme.Space.m) {
                        FoodMacroValue(label: "Protein", grams: recipe.perServing.protein, tint: Theme.protein)
                        FoodMacroValue(label: "Kohlenhydrate", grams: recipe.perServing.carbs, tint: Theme.carbs)
                        FoodMacroValue(label: "Fett", grams: recipe.perServing.fat, tint: Theme.fat)
                    }
                }

                Card {
                    CardHeader(title: "Gesamt · \(recipe.servings) Portionen", symbol: "sum")
                    FoodNutrientTable(nutrients: recipe.total)
                }

                Card {
                    CardHeader(title: "Pro 100 g", symbol: "scalemass")
                    if let per100 = recipe.per100 {
                        FoodNutrientTable(nutrients: per100)
                        Text(recipe.cookedWeightG == nil
                             ? "Berechnet aus dem Rohgewicht der Zutaten. Mit dem Gewicht nach dem Kochen werden die Werte genauer."
                             : "Berechnet aus dem Gewicht nach dem Kochen (\(Fmt.number(recipe.cookedWeightG ?? 0)) g).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nicht berechenbar – füge Zutaten mit Gewicht hinzu.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Card {
                    CardHeader(title: "Zutaten", symbol: "list.bullet")
                    ForEach(recipe.ingredients) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.number(item.grams)) g · \(Fmt.number(item.nutrients.kcal)) kcal")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if recipe.ingredients.isEmpty {
                        Text("Keine Zutaten").foregroundStyle(.secondary)
                    }
                }

                if !recipe.instructions.isEmpty {
                    Card {
                        CardHeader(title: "Zubereitung", symbol: "text.alignleft")
                        Text(recipe.instructions).font(.body)
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 96)
        }
        .screenBackground()
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Bearbeiten", systemImage: "pencil") { isEditing = true }
                    Button(recipe.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten", systemImage: recipe.isFavorite ? "star.slash" : "star") {
                        recipe.isFavorite.toggle()
                        context.saveQuietly()
                    }
                    Button("Duplizieren", systemImage: "plus.square.on.square") {
                        NutritionRecipeActions.duplicate(recipe, in: context)
                    }
                    Divider()
                    Button("Löschen", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Rezept-Optionen")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton(title: "Portion hinzufügen", systemImage: "plus", isEnabled: !recipe.ingredients.isEmpty) {
                isLogging = true
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.Space.xs)
        }
        .sheet(isPresented: $isEditing) {
            NutritionRecipeEditor(recipe: recipe)
        }
        .sheet(isPresented: $isLogging) {
            NutritionRecipePortionSheet(recipe: recipe, meal: MealType.suggested(), day: router.nutritionDay)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Rezept löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(recipe)
                context.saveQuietly()
                dismiss()
            }
        } message: {
            Text("Bereits erfasste Portionen im Tagebuch bleiben erhalten.")
        }
    }
}

// MARK: - Portion erfassen

struct NutritionRecipePortionSheet: View {
    let recipe: Recipe
    let day: Date
    var onLogged: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @State private var meal: MealType
    @State private var portions: Double = 1

    init(recipe: Recipe, meal: MealType, day: Date, onLogged: (() -> Void)? = nil) {
        self.recipe = recipe
        self.day = day
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $portions, in: 0.25...20, step: 0.25) {
                        HStack {
                            Text("Portionen")
                            Spacer()
                            Text(Fmt.decimal(portions, maxDigits: 2)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Energie", value: Fmt.energyWithUnit(recipe.perServing.kcal * portions, unit: prefs.energyUnit))
                    LabeledContent("Protein", value: "\(Fmt.decimal(recipe.perServing.protein * portions)) g")
                } footer: {
                    Text("Wird als Rezept-Eintrag mit dem aktuellen Nährwertstand gespeichert.")
                }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        NutritionMealLogger.log(recipe, portions: portions, meal: meal, day: day, in: context)
                        onLogged?()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Editor

struct NutritionRecipeEditor: View {
    let recipe: Recipe?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @State private var name: String
    @State private var servings: Int
    @State private var cookedWeight: Double?
    @State private var ingredients: [MealComponent]
    @State private var instructions: String
    @State private var pickingIngredient = false

    init(recipe: Recipe?) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _servings = State(initialValue: recipe?.servings ?? 2)
        _cookedWeight = State(initialValue: recipe?.cookedWeightG)
        _ingredients = State(initialValue: recipe?.ingredients ?? [])
        _instructions = State(initialValue: recipe?.instructions ?? "")
    }

    private var total: Nutrients { ingredients.reduce(Nutrients.zero) { $0 + $1.nutrients } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name des Rezepts", text: $name)
                    Stepper(value: $servings, in: 1...50) {
                        HStack {
                            Text("Portionen")
                            Spacer()
                            Text("\(servings)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    NumberField(title: "Gewicht gekocht", value: $cookedWeight, unit: "g", fractionDigits: 0)
                } footer: {
                    Text("Optional: Gesamtgewicht nach dem Kochen für genaue Werte pro 100 g.")
                }

                Section {
                    ForEach($ingredients) { $item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(1)
                                Text("\(Fmt.number(item.nutrients.kcal)) kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("g", value: $item.grams, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(maxWidth: 70)
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        pickingIngredient = true
                    } label: {
                        Label("Zutat hinzufügen", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Zutaten")
                } footer: {
                    if !ingredients.isEmpty {
                        Text("Gesamt \(Fmt.energyWithUnit(total.kcal, unit: prefs.energyUnit)) · pro Portion \(Fmt.energyWithUnit(total.kcal / Double(max(servings, 1)), unit: prefs.energyUnit))")
                    }
                }

                Section("Zubereitung") {
                    TextField("Notizen zur Zubereitung", text: $instructions, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(recipe == nil ? "Neues Rezept" : "Rezept bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty)
                }
            }
            .sheet(isPresented: $pickingIngredient) {
                NutritionIngredientPicker { food, grams in
                    ingredients.append(MealComponent(foodID: food.id, name: food.name, brand: food.brand, grams: grams,
                                                     per100: food.per100, qualityRaw: food.qualityRaw))
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target: Recipe
        if let recipe {
            target = recipe
            target.name = trimmed
        } else {
            target = Recipe(name: trimmed)
            context.insert(target)
        }
        target.servings = servings
        target.cookedWeightG = (cookedWeight ?? 0) > 0 ? cookedWeight : nil
        target.ingredients = ingredients
        target.instructions = instructions
        AuditLog.record(context, actor: .user, summary: recipe == nil ? "Rezept „\(trimmed)“ angelegt" : "Rezept „\(trimmed)“ geändert",
                        entityType: "Recipe", entityID: target.id.uuidString)
        context.saveQuietly()
        dismiss()
    }
}

// MARK: - Zutat wählen

struct NutritionIngredientPicker: View {
    var onPick: (FoodItem, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Query(filter: #Predicate<FoodItem> { $0.isHidden == false }) private var foods: [FoodItem]

    @State private var query = ""
    @State private var selected: FoodItem?
    @State private var grams: Double = 100

    private var results: [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return Array(foods.sorted { $0.useCount > $1.useCount }.prefix(30))
        }
        return FoodRepository.search(foods, query: q)
    }

    var body: some View {
        NavigationStack {
            List {
                if let selected {
                    Section("Menge für \(selected.name)") {
                        HStack {
                            TextField("Menge", value: $grams, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                            Text(selected.unitSymbol).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.energyWithUnit(selected.per100.forGrams(grams).kcal, unit: prefs.energyUnit))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if !selected.servings.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(selected.servings) { s in
                                        ChoiceChip(title: s.label, isSelected: abs(grams - s.grams) < 0.5) { grams = s.grams }
                                    }
                                }
                            }
                        }
                        Button("Übernehmen") {
                            onPick(selected, grams)
                            dismiss()
                        }
                        .disabled(grams <= 0)
                    }
                }
                Section(query.isEmpty ? "Häufig verwendet" : "Ergebnisse") {
                    ForEach(results) { food in
                        Button {
                            selected = food
                            grams = food.servings.first?.grams ?? 100
                        } label: {
                            NutritionFoodRow(food: food, energyUnit: prefs.energyUnit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Zutat suchen")
            .navigationTitle("Zutat hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
        }
    }
}
