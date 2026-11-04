import SwiftUI
import SwiftData

/// Lebensmittel suchen und hinzufügen – lokal, über Open Food Facts, per Barcode, Foto,
/// Schnelleintrag, gespeicherte Mahlzeiten und Rezepte.
struct FoodSearchView: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @Query(filter: #Predicate<FoodItem> { $0.isHidden == false }) private var foods: [FoodItem]
    @Query(sort: \SavedMeal.useCount, order: .reverse) private var savedMeals: [SavedMeal]
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]

    @State private var meal: MealType
    @State private var query = ""
    @State private var forceOnline = false
    @State private var online: [NutritionProductDTO] = []
    @State private var onlineState: OnlineState = .idle
    @State private var selectedFood: FoodItem?
    @State private var habitFoods: [FoodItem] = []
    @State private var activeSheet: SearchSheet?
    @State private var recipeToLog: Recipe?
    @State private var toast: String?
    @State private var addedCount = 0

    init(meal: MealType, day: Date) {
        self.day = day
        _meal = State(initialValue: meal)
    }

    private enum OnlineState: Equatable { case idle, loading, done, empty, failed }

    private enum SearchSheet: String, Identifiable {
        case barcode, photo, quick, custom
        var id: String { rawValue }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var localResults: [FoodItem] { FoodRepository.search(foods, query: trimmedQuery) }

    private var recentFoods: [FoodItem] {
        Array(foods.filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(8))
    }

    private var favoriteFoods: [FoodItem] {
        foods.filter(\.isFavorite).sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    entryPoints
                    browseSections
                } else {
                    searchSections
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle(meal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                Picker("Mahlzeit", selection: $meal) {
                    ForEach(MealType.allCases) { m in
                        Label(m.title, systemImage: m.symbol).tag(m)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Lebensmittel oder Marke suchen")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(addedCount > 0 ? "Fertig" : "Schliessen") { dismiss() }
                }
            }
            .task(id: "\(trimmedQuery)|\(forceOnline)") { await searchOnline() }
            .task(id: meal) { loadHabitFoods() }
            .sheet(item: $selectedFood) { food in
                FoodAmountSheet(food: food, meal: meal, day: day, source: .search) { entry in
                    didLog(entry.name)
                }
                .presentationDetents([.large])
            }
            .sheet(item: $recipeToLog) { recipe in
                NutritionRecipePortionSheet(recipe: recipe, meal: meal, day: day) {
                    didLog(recipe.name)
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .barcode:
                    BarcodeScannerSheet(meal: meal, day: day) { didLog("Produkt") }
                case .photo:
                    PhotoFoodSheet(meal: meal, day: day) { didLog("Foto-Einträge") }
                case .quick:
                    NutritionQuickEntrySheet(meal: meal, day: day) { name in didLog(name) }
                        .presentationDetents([.medium, .large])
                case .custom:
                    NutritionCustomFoodEditor(barcode: nil, initialName: trimmedQuery) { food in
                        activeSheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            selectedFood = food
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    NutritionToast(text: toast)
                        .padding(.bottom, Theme.Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast) {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.smooth) { self.toast = nil }
                        }
                }
            }
        }
    }

    // MARK: Abschnitte

    private var entryPoints: some View {
        Section {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    entryButton("Barcode", "barcode.viewfinder", .barcode)
                    entryButton("Foto", "camera", .photo)
                    entryButton("Schnell", "bolt", .quick)
                    entryButton("Eigenes", "square.and.pencil", .custom)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    private func entryButton(_ title: String, _ symbol: String, _ sheet: SearchSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.medium))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 18))
    }

    @ViewBuilder
    private var browseSections: some View {
        if !recentFoods.isEmpty {
            Section("Zuletzt verwendet") {
                ForEach(recentFoods) { foodRow($0) }
            }
        }

        if !habitFoods.isEmpty {
            Section {
                ForEach(habitFoods) { foodRow($0) }
            } header: {
                Text("Häufig bei \(meal.title)")
            } footer: {
                Text("Vorschläge basierend auf deinen bisherigen Einträgen.")
            }
        }

        if !favoriteFoods.isEmpty {
            Section("Favoriten") {
                ForEach(favoriteFoods) { foodRow($0) }
            }
        }

        if !savedMeals.isEmpty {
            Section("Gespeicherte Mahlzeiten") {
                ForEach(savedMeals.prefix(6)) { saved in
                    Button {
                        NutritionMealLogger.log(saved, meal: meal, day: day, in: context)
                        didLog(saved.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name).foregroundStyle(.primary)
                                Text("\(saved.items.count) Bestandteile · \(Fmt.energyWithUnit(saved.total.kcal, unit: prefs.energyUnit))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Fügt alle Bestandteile hinzu")
                }
            }
        }

        if !recipes.isEmpty {
            Section("Rezepte") {
                ForEach(recipes.prefix(6)) { recipe in
                    Button {
                        recipeToLog = recipe
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name).foregroundStyle(.primary)
                                Text("pro Portion \(Fmt.energyWithUnit(recipe.perServing.kcal, unit: prefs.energyUnit))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if recentFoods.isEmpty && favoriteFoods.isEmpty && savedMeals.isEmpty {
            Section {
                Text("Suche nach Lebensmitteln oder scanne einen Barcode. Häufig genutzte Lebensmittel erscheinen hier automatisch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        let local = localResults
        if !local.isEmpty {
            Section("Katalog") {
                ForEach(local) { foodRow($0) }
            }
        }

        Section {
            switch onlineState {
            case .idle:
                if local.count >= 6 {
                    Button("Auch in Open Food Facts suchen") { forceOnline = true }
                } else if trimmedQuery.count < 3 {
                    Text("Mindestens 3 Zeichen für die Online-Suche eingeben.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .loading:
                HStack(spacing: 10) {
                    SwiftUI.ProgressView()
                    Text("Suche in Open Food Facts …").foregroundStyle(.secondary)
                }
            case .empty:
                Text("Keine weiteren Produkte gefunden.").foregroundStyle(.secondary)
            case .failed:
                Text("Online-Suche nicht verfügbar. Du kannst das Lebensmittel selbst anlegen.")
                    .foregroundStyle(.secondary)
            case .done:
                ForEach(online) { product in
                    onlineRow(product)
                }
            }
            Button {
                activeSheet = .custom
            } label: {
                Label("„\(trimmedQuery)“ selbst anlegen", systemImage: "square.and.pencil")
            }
        } header: {
            if onlineState == .done { Text("Open Food Facts") }
        } footer: {
            if onlineState == .done {
                Text("Community-Daten, lizenziert unter der Open Database License (ODbL). Bitte Werte mit der Verpackung vergleichen.")
            }
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        Button {
            selectedFood = food
        } label: {
            NutritionFoodRow(food: food, energyUnit: prefs.energyUnit)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button {
                food.isFavorite.toggle()
                context.saveQuietly()
            } label: {
                Label(food.isFavorite ? "Entfernen" : "Favorit", systemImage: food.isFavorite ? "star.slash" : "star")
            }
            .tint(Theme.carbs)
        }
    }

    private func onlineRow(_ product: NutritionProductDTO) -> some View {
        Button {
            let item = FoodRepository.insert(product, in: context)
            selectedFood = item
        } label: {
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).lineLimit(1)
                    Text([product.brand, "\(Fmt.number(product.per100.kcal)) kcal / 100 \(product.isLiquid ? "ml" : "g")"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if product.quality == .incomplete {
                    Image(systemName: DataQuality.incomplete.symbol)
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("Unvollständige Nährwerte")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Logik

    private func searchOnline() async {
        let q = trimmedQuery
        guard q.count >= 3 else {
            online = []
            onlineState = .idle
            forceOnline = false
            return
        }
        let localCount = FoodRepository.search(foods, query: q).count
        guard localCount < 6 || forceOnline else {
            online = []
            onlineState = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            return
        }
        onlineState = .loading
        do {
            let results = try await OpenFoodFactsClient.search(q)
            guard !Task.isCancelled else { return }
            let known = Set(foods.compactMap(\.barcode))
            online = results.filter { dto in dto.barcode.map { !known.contains($0) } ?? true }
            onlineState = online.isEmpty ? .empty : .done
        } catch {
            guard !Task.isCancelled else { return }
            onlineState = .failed
        }
    }

    private func loadHabitFoods() {
        let since = Date.now.adding(days: -42)
        let mealRaw = meal.rawValue
        let descriptor = FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.date >= since && $0.mealRaw == mealRaw })
        let recent = (try? context.fetch(descriptor)) ?? []
        var counts: [UUID: Int] = [:]
        for entry in recent {
            if let id = entry.foodID { counts[id, default: 0] += 1 }
        }
        let top = counts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.prefix(6).map { $0.key }
        habitFoods = top.compactMap { id in foods.first { $0.id == id } }
    }

    private func didLog(_ name: String) {
        addedCount += 1
        withAnimation(.smooth) { toast = "\(name) hinzugefügt" }
    }
}

// MARK: - Zeile

struct NutritionFoodRow: View {
    let food: FoodItem
    let energyUnit: EnergyUnit

    private var subtitle: String {
        var parts: [String] = []
        if let brand = food.brand, !brand.isEmpty { parts.append(brand) }
        if let serving = food.servings.first {
            let kcal = food.per100.forGrams(serving.grams).kcal
            parts.append("\(serving.label) · \(Fmt.energyWithUnit(kcal, unit: energyUnit))")
        } else {
            parts.append("\(Fmt.energyWithUnit(food.per100.kcal, unit: energyUnit)) / 100 \(food.unitSymbol)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(food.name).lineLimit(1)
                    if food.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.carbs)
                            .accessibilityLabel("Favorit")
                    }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if food.quality != .reference && food.quality != .verified {
                Image(systemName: food.quality.symbol)
                    .font(.footnote)
                    .foregroundStyle(food.quality.tint)
                    .accessibilityLabel(food.quality.title)
            }
        }
        .contentShape(Rectangle())
    }
}
