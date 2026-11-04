import SwiftUI
import SwiftData

/// Logik für Gewohnheiten.
@MainActor
enum HabitStore {
    static func toggle(_ habit: Habit, on date: Date, checks: [HabitCheck], in context: ModelContext) {
        let key = DayKey.make(date)
        if let existing = checks.first(where: { $0.habitID == habit.id && $0.dayKey == key }) {
            context.delete(existing)
        } else {
            context.insert(HabitCheck(habitID: habit.id, date: date))
        }
        context.saveQuietly()
    }

    /// Aufeinanderfolgende erledigte Tage bis heute (heute zählt, falls erledigt).
    static func streak(for habit: Habit, checks: [HabitCheck]) -> Int {
        let keys = Set(checks.filter { $0.habitID == habit.id }.map(\.dayKey))
        var count = 0
        var day = Date.now
        if !keys.contains(DayKey.make(day)) { day = day.adding(days: -1) }
        while keys.contains(DayKey.make(day)) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }
}

/// Eigene, tägliche Gewohnheiten (Modul „Gewohnheiten“).
struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.order) private var habits: [Habit]
    @Query private var recentChecks: [HabitCheck]
    @State private var showsEditor = false
    @State private var editing: Habit?

    init() {
        let start = Date.now.adding(days: -60).startOfDay
        _recentChecks = Query(filter: #Predicate<HabitCheck> { $0.date >= start })
    }

    var body: some View {
        List {
            if habits.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Gewohnheiten", systemImage: "checkmark.circle")
                } description: {
                    Text("Kleine, tägliche Schritte machen den Unterschied. Lege deine erste Gewohnheit an.")
                } actions: {
                    Button("Gewohnheit anlegen") { showsEditor = true }
                        .buttonStyle(.glassProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section("Heute") {
                    ForEach(habits) { habit in
                        HabitToggleRow(habit: habit, isDone: isDone(habit)) {
                            HabitStore.toggle(habit, on: .now, checks: recentChecks, in: context)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { archive(habit) } label: {
                                Label("Archivieren", systemImage: "archivebox")
                            }
                            Button { editing = habit } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                        }
                    }
                    .onMove(perform: move)
                }

                Section("Letzte 14 Tage") {
                    ForEach(habits) { habit in
                        HabitHistoryRow(habit: habit, checks: recentChecks)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gewohnheiten")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Gewohnheit hinzufügen")
            }
            if !habits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .sheet(isPresented: $showsEditor) {
            HabitEditorSheet(habit: nil, nextOrder: (habits.last?.order ?? 0) + 1)
        }
        .sheet(item: $editing) { habit in
            HabitEditorSheet(habit: habit, nextOrder: habit.order)
        }
    }

    private func isDone(_ habit: Habit) -> Bool {
        let key = DayKey.today
        return recentChecks.contains { $0.habitID == habit.id && $0.dayKey == key }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = habits
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in ordered.enumerated() { habit.order = index }
        context.saveQuietly()
    }

    private func archive(_ habit: Habit) {
        habit.isArchived = true
        context.saveQuietly()
    }
}

private struct HabitHistoryRow: View {
    let habit: Habit
    let checks: [HabitCheck]

    var body: some View {
        let keys = DayKey.range(count: 14)
        let done = Set(checks.filter { $0.habitID == habit.id }.map(\.dayKey))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(habit.name, systemImage: habit.symbol)
                    .font(.subheadline)
                Spacer()
                let streak = HabitStore.streak(for: habit, checks: checks)
                if streak > 0 {
                    Text("\(streak) Tage in Folge")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Capsule()
                        .fill(done.contains(key) ? Theme.positive : Theme.fill)
                        .frame(height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(keys.filter { done.contains($0) }.count) von 14 Tagen erledigt")
        }
        .padding(.vertical, 4)
    }
}

private struct HabitEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let habit: Habit?
    let nextOrder: Int

    @State private var name = ""
    @State private var symbol = "checkmark.circle"

    private let symbols = ["checkmark.circle", "drop", "leaf", "bed.double", "figure.walk", "figure.flexibility",
                           "book", "sun.max", "moon", "fork.knife", "carrot", "brain.head.profile", "heart", "pills"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, z. B. 10 Minuten Mobility", text: $name)
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.body)
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(symbol == item ? Color.white : Color.primary)
                                    .background(symbol == item ? Theme.accent : Theme.fill, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(habit == nil ? "Neue Gewohnheit" : "Gewohnheit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let habit {
                    name = habit.name
                    symbol = habit.symbol
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let habit {
            habit.name = trimmed
            habit.symbol = symbol
        } else {
            context.insert(Habit(name: trimmed, symbol: symbol, order: nextOrder))
        }
        context.saveQuietly()
        dismiss()
    }
}
