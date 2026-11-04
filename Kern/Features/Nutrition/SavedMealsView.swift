import SwiftUI
import SwiftData

/// Gespeicherte Mahlzeitenkombinationen – mit einem Tipp erneut hinzufügen.
struct SavedMealsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    @Query(sort: \SavedMeal.useCount, order: .reverse) private var meals: [SavedMeal]

    @State private var renaming: SavedMeal?
    @State private var newName = ""
    @State private var expanded: Set<UUID> = []
    @State private var toast: String?

    private var day: Date { router.nutritionDay }

    var body: some View {
        List {
            if meals.isEmpty {
                ContentUnavailableView {
                    Label("Keine gespeicherten Mahlzeiten", systemImage: "square.stack")
                } description: {
                    Text("Speichere eine Mahlzeit im Tagebuch über das Menü einer Mahlzeit („Als Mahlzeit speichern“), um sie später mit einem Tipp erneut hinzuzufügen.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(meals) { saved in
                        row(saved)
                    }
                } footer: {
                    Text("Hinzufügen erfolgt zu \(Fmt.day(day)). Die gespeicherten Nährwerte entsprechen dem Stand beim Speichern.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gespeicherte Mahlzeiten")
        .alert("Umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Sichern") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if let renaming, !trimmed.isEmpty {
                    renaming.name = trimmed
                    context.saveQuietly()
                }
                renaming = nil
            }
            Button("Abbrechen", role: .cancel) { renaming = nil }
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

    private func row(_ saved: SavedMeal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Button {
                    withAnimation(.snappy) {
                        if expanded.contains(saved.id) { expanded.remove(saved.id) } else { expanded.insert(saved.id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.name).foregroundStyle(.primary)
                        Text("\(saved.meal.title) · \(saved.items.count) Bestandteile · \(Fmt.energyWithUnit(saved.total.kcal, unit: prefs.energyUnit))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Zeigt die Bestandteile")

                Menu {
                    ForEach(MealType.allCases) { meal in
                        Button("Zu \(meal.title)", systemImage: meal.symbol) { add(saved, to: meal) }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                } primaryAction: {
                    add(saved, to: saved.meal)
                }
                .accessibilityLabel("\(saved.name) hinzufügen")
            }

            if expanded.contains(saved.id) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(saved.items) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.number(item.grams)) g · \(Fmt.number(item.nutrients.kcal)) kcal")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                }
                .padding(.top, 2)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                context.delete(saved)
                context.saveQuietly()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            Button {
                newName = saved.name
                renaming = saved
            } label: {
                Label("Umbenennen", systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
    }

    private func add(_ saved: SavedMeal, to meal: MealType) {
        NutritionMealLogger.log(saved, meal: meal, day: day, in: context)
        withAnimation(.smooth) { toast = "\(saved.name) zu \(meal.title) hinzugefügt" }
    }
}
