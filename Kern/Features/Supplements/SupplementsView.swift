import SwiftUI
import SwiftData

/// Supplement-Routinen, Einnahmen, Vorrat und Inhaltsstoff-Übersicht.
struct SupplementsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \Supplement.name) private var supplements: [Supplement]
    @Query(sort: \SupplementIntake.date, order: .reverse) private var intakes: [SupplementIntake]

    @State private var isAdding = false
    @State private var showsIngredients = false

    private var active: [Supplement] { supplements.filter(\.isActive) }
    private var paused: [Supplement] { supplements.filter { !$0.isActive } }
    private var todaySlots: [SupplementSlot] { SupplementPlanner.slots(on: .now, supplements: active, intakes: intakes) }
    private var asNeeded: [Supplement] { active.filter { $0.frequency == .asNeeded } }
    private var lowStock: [Supplement] { active.filter(\.isLowOnStock) }

    var body: some View {
        List {
            if supplements.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Noch keine Supplements", systemImage: "pills")
                    } description: {
                        Text("Lege deine Routine an – per Barcode, Etikett-Foto oder manuell.")
                    } actions: {
                        Button("Supplement hinzufügen") { isAdding = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }

            if !lowStock.isEmpty {
                Section {
                    ForEach(lowStock) { s in
                        Label {
                            Text("\(s.name): noch \(Fmt.number(s.stockServings ?? 0)) Portionen")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Vorrat")
                }
            }

            if !todaySlots.isEmpty {
                todaySection
            }

            if !asNeeded.isEmpty {
                Section("Nach Bedarf") {
                    ForEach(asNeeded) { s in
                        let takenToday = intakes.filter { $0.supplementID == s.id && $0.dayKey == DayKey.today }.count
                        HStack {
                            RowLabel(title: s.name, subtitle: takenToday > 0 ? "Heute \(takenToday)× dokumentiert" : s.servingLabel,
                                     symbol: s.form.symbol, tint: Theme.supplement)
                            Button("Erfassen") {
                                LogService.logIntake(s, in: context)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }

            if !active.isEmpty {
                Section("Meine Supplements") {
                    ForEach(active) { s in row(s) }
                }
            }
            if !paused.isEmpty {
                Section("Pausiert") {
                    ForEach(paused) { s in row(s) }
                }
            }

            if !active.isEmpty {
                ingredientSection
            }

            Section {
                InfoNote(text: "Kern spricht keine Dosierungsempfehlungen aus und beurteilt keine Wechselwirkungen mit Medikamenten. Bitte besprich die Einnahme mit einer Fachperson und nutze geprüfte Fachinformationen.",
                         symbol: "stethoscope")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Supplements")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Hinzufügen", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) { SupplementAddSheet() }
    }

    // MARK: Heute

    private var todaySection: some View {
        let slots = todaySlots
        let taken = slots.filter(\.isTaken).count
        let groups = Dictionary(grouping: slots, by: \.minute).sorted { $0.key < $1.key }
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(taken) von \(slots.count) eingenommen")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(Fmt.percent(slots.isEmpty ? 0 : Double(taken) / Double(slots.count)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LinearMeter(progress: slots.isEmpty ? 0 : Double(taken) / Double(slots.count), tint: Theme.supplement)
            }
            .padding(.vertical, 4)

            ForEach(groups, id: \.key) { group in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(Fmt.minuteOfDay(group.key))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    ForEach(group.value) { slot in
                        SupplementSlotRow(slot: slot)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Heute")
        }
    }

    private func row(_ s: Supplement) -> some View {
        NavigationLink {
            SupplementDetailView(supplement: s)
        } label: {
            HStack {
                RowLabel(title: s.name, subtitle: subtitle(s), symbol: s.form.symbol, tint: s.isActive ? Theme.supplement : .secondary)
                if s.isLowOnStock { Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning).font(.footnote) }
                if s.quality == .aiUnconfirmed { QualityBadge(quality: s.quality) }
            }
        }
    }

    private func subtitle(_ s: Supplement) -> String {
        var parts = ["\(Fmt.decimal(s.servingsPerIntake)) × \(s.servingLabel)"]
        if s.frequency != .asNeeded {
            parts.append(s.scheduleMinutes.sorted().map(Fmt.minuteOfDay).joined(separator: ", "))
        }
        if let adherence = SupplementPlanner.adherence(of: s, intakes: intakes, days: 14) {
            parts.append("\(Fmt.percent(adherence)) eingehalten")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Inhaltsstoffe

    @ViewBuilder
    private var ingredientSection: some View {
        let totals = SupplementPlanner.plannedTotals(active)
        let overlaps = totals.filter { $0.products.count >= 2 }
        if !totals.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showsIngredients) {
                    ForEach(totals) { total in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(total.title)
                                Text(total.products.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(SupplementPlanner.formatAmount(total.amount)) \(total.unit)")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    foodComparison(totals)
                } label: {
                    Label("Inhaltsstoffe pro Tag (geplant)", systemImage: "list.bullet.rectangle")
                }

                ForEach(overlaps) { overlap in
                    Label {
                        Text("Mögliche Überschneidung: \(overlap.title) ist in \(overlap.products.joined(separator: " und ")) enthalten.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "square.on.square").foregroundStyle(Theme.warning)
                    }
                }
            } header: {
                Text("Übersicht")
            } footer: {
                Text("Summen basieren auf deinen eigenen Angaben und Etikettenwerten. Sie sind keine Bewertung.")
            }
        }
    }

    @ViewBuilder
    private func foodComparison(_ totals: [SupplementIngredientTotal]) -> some View {
        let start = Date.now.startOfDay
        let foods = ProgressData.foodEntries(in: context, from: start, to: start.adding(days: 1))
        let foodTotal = foods.reduce(Nutrients.zero) { $0 + $1.nutrients }
        let taken = SupplementPlanner.takenTotals(active, intakes: intakes)
        let rows = SupplementPlanner.comparableKeys.filter { key in
            totals.contains { $0.key == key.key } || SupplementPlanner.foodValue(for: key.key, in: foodTotal) != nil
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Heute aus Lebensmitteln und Supplements")
                    .font(.footnote.weight(.semibold))
                    .padding(.top, Theme.Space.xs)
                Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("Essen").font(.caption2Strong).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text("Supplements").font(.caption2Strong).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    }
                    ForEach(rows, id: \.key) { row in
                        GridRow {
                            Text(row.title).font(.caption)
                            Text(SupplementPlanner.foodValue(for: row.key, in: foodTotal).map { "\(SupplementPlanner.formatAmount($0)) \(row.unit)" } ?? "–")
                                .font(.caption.monospacedDigit())
                            Text(taken[row.key].map { "\(SupplementPlanner.formatAmount($0)) \(row.unit)" } ?? "–")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
                Text("Nährwerte aus Lebensmitteln sind nur enthalten, soweit sie in den Produktdaten vorliegen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Zeile für eine geplante Einnahme mit Bestätigen/Rückgängig.
struct SupplementSlotRow: View {
    @Environment(\.modelContext) private var context
    let slot: SupplementSlot

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                withAnimation(.snappy) {
                    if let intake = slot.intake {
                        SupplementPlanner.undo(intake, in: context)
                    } else {
                        LogService.logIntake(slot.supplement, scheduledMinute: slot.minute, in: context)
                    }
                }
            } label: {
                Image(systemName: slot.isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(slot.isTaken ? Theme.supplement : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: slot.isTaken)
            .accessibilityLabel(slot.isTaken ? "\(slot.supplement.name) – Einnahme zurücknehmen" : "\(slot.supplement.name) als eingenommen markieren")

            VStack(alignment: .leading, spacing: 1) {
                Text(slot.supplement.name)
                    .strikethrough(slot.isTaken, color: .secondary)
                    .foregroundStyle(slot.isTaken ? .secondary : .primary)
                Text("\(Fmt.decimal(slot.supplement.servingsPerIntake)) × \(slot.supplement.servingLabel)\(slot.intake.map { " · \(Fmt.time($0.date))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Dashboard-Karte

struct SupplementsTodayCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Supplement.name) private var supplements: [Supplement]
    @Query(sort: \SupplementIntake.date, order: .reverse) private var intakes: [SupplementIntake]

    private var slots: [SupplementSlot] {
        SupplementPlanner.slots(on: .now, supplements: supplements.filter(\.isActive), intakes: intakes)
    }

    var body: some View {
        let all = slots
        let taken = all.filter(\.isTaken).count
        let currentMinute = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        let next = all.first { !$0.isTaken && $0.minute <= currentMinute + 60 } ?? all.first { !$0.isTaken }
        let lowStock = supplements.filter { $0.isActive && $0.isLowOnStock }

        Card {
            CardHeader(title: "Supplements heute", symbol: "pills", tint: Theme.supplement) {
                NavigationLink(value: AppDestination.supplements) {
                    Text("Alle").font(.subheadline.weight(.medium))
                }
            }
            if all.isEmpty {
                Text(supplements.isEmpty ? "Noch keine Routine angelegt." : "Heute ist nichts eingeplant.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    StatValue(value: "\(taken)/\(all.count)", label: "eingenommen", valueFont: .metricMedium)
                    Spacer()
                }
                LinearMeter(progress: Double(taken) / Double(all.count), tint: Theme.supplement)
                if let next {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.supplement.name).font(.subheadline.weight(.medium))
                            Text("Geplant \(Fmt.minuteOfDay(next.minute))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            LogService.logIntake(next.supplement, scheduledMinute: next.minute, in: context)
                        } label: {
                            Label("Eingenommen", systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    }
                } else {
                    Label("Alles für heute erledigt", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.supplement)
                }
            }
            if let low = lowStock.first {
                Label("\(low.name): Vorrat geht zur Neige", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}
