import SwiftUI
import SwiftData
import Charts

// MARK: - Diagramm

/// Gewichtsdiagramm: Messpunkte dezent, geglätteter Trend als Linie. Keine Flächenfüllung.
struct ProgressWeightChart: View {
    let entries: [WeightEntry]
    var unit: WeightUnit
    var range: ProgressRange = .quarter
    var compact: Bool = false

    private var filtered: [WeightEntry] {
        guard let start = range.startDate else { return entries }
        return entries.filter { $0.date >= start }
    }

    private var raw: [ProgressChartPoint] {
        filtered.map { ProgressChartPoint(date: $0.date, value: unit.fromKg($0.kg)) }
    }

    private var trend: [ProgressChartPoint] {
        // Trend über alle Daten glätten, dann auf den Zeitraum beschränken.
        let smooth = AdaptiveEnergyEstimator.smoothedTrend(entries.map { (date: $0.date, kg: $0.kg) })
        let start = range.startDate ?? .distantPast
        return smooth.filter { $0.date >= start }.map { ProgressChartPoint(date: $0.date, value: unit.fromKg($0.kg)) }
    }

    private var domain: ClosedRange<Double> {
        let values = raw.map(\.value) + trend.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 0.6)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            if !compact {
                ForEach(raw) { point in
                    PointMark(x: .value("Datum", point.date), y: .value("Messung", point.value))
                        .foregroundStyle(Theme.weight.opacity(0.35))
                        .symbolSize(22)
                }
            }
            ForEach(trend) { point in
                LineMark(x: .value("Datum", point.date), y: .value("Trend", point.value),
                         series: .value("Reihe", "Trend"))
                    .foregroundStyle(Theme.weight)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: compact ? 2 : 2.5, lineCap: .round))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
        .accessibilityElement()
        .accessibilityLabel("Gewichtsverlauf")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = trend.first, let last = trend.last else { return "Keine Daten" }
        return "Trend von \(Fmt.decimal(first.value)) auf \(Fmt.decimal(last.value)) \(unit.symbol)"
    }
}

// MARK: - Gewichtsverlauf

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @State private var range: ProgressRange = .quarter

    private var ascending: [WeightEntry] { entries.reversed() }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(ProgressRange.allCases) { r in
                            Text(r.title).tag(r).accessibilityLabel(r.accessibilityTitle)
                        }
                    }
                    .pickerStyle(.segmented)

                    if entries.count >= 2 {
                        ProgressWeightChart(entries: ascending, unit: prefs.weightUnit, range: range)
                            .frame(height: 220)
                    } else {
                        Text("Ab zwei Messungen erscheint hier dein Verlauf.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }

                    if let trend = AdaptiveEnergyEstimator.weeklyTrend(ascending.map { (date: $0.date, kg: $0.kg) }) {
                        HStack {
                            StatValue(value: Fmt.signed(prefs.weightUnit.fromKg(trend), digits: 2), unit: "\(prefs.weightUnit.symbol)/Woche",
                                      label: "Trend der letzten 3 Wochen")
                            Spacer()
                            if let latest = entries.first {
                                StatValue(value: Fmt.weight(latest.kg, unit: prefs.weightUnit), unit: prefs.weightUnit.symbol,
                                          label: "Letzte Messung")
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }

            Section {
                InfoNote(text: "Tägliche Schwankungen von 0.5–1.5 kg durch Wasser, Salz und Verdauung sind normal. Kern bewertet deshalb den geglätteten Trend, nicht einzelne Messungen.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Messungen") {
                if entries.isEmpty {
                    ContentUnavailableView("Noch keine Messungen", systemImage: "scalemass",
                                           description: Text("Erfasse dein Gewicht manuell, über den Coach oder Apple Health."))
                }
                ForEach(entries) { entry in
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: entry.sourceSymbol)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.mediumDate(entry.date))
                            Text("\(Fmt.time(entry.date)) · \(entry.source.title)\(entry.note.isEmpty ? "" : " · \(entry.note)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(Fmt.weightWithUnit(entry.kg, unit: prefs.weightUnit))
                            .font(.body.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete(perform: delete)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gewicht")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { router.present(.weightEntry) } label: {
                    Label("Gewicht erfassen", systemImage: "plus")
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            AuditLog.record(context, actor: .user,
                            summary: "Gewichtseintrag \(Fmt.decimal(entry.kg)) kg vom \(Fmt.shortDate(entry.date)) gelöscht",
                            entityType: EntityType.weight, entityID: entry.id.uuidString)
            context.delete(entry)
        }
        context.saveQuietly()
    }
}

// MARK: - Erfassen

struct WeightEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    @State private var value: Double?
    @State private var date: Date = .now
    @State private var note = ""
    @FocusState private var focused: Bool

    private var kg: Double? { value.map { prefs.weightUnit.toKg($0) } }
    private var isValid: Bool { (kg ?? 0) >= 25 && (kg ?? 0) <= 350 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                            .font(.metricLarge)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .focused($focused)
                            .accessibilityLabel("Gewicht")
                        Text(prefs.weightUnit.symbol)
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if let last = entries.first, let kg, isValid {
                        Text("\(Fmt.signed(prefs.weightUnit.fromKg(kg - last.kg), digits: 1)) \(prefs.weightUnit.symbol) seit \(Fmt.day(last.date))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    DatePicker("Zeitpunkt", selection: $date, in: ...Date.now)
                    TextField("Notiz (optional)", text: $note)
                }
                Section {
                    InfoNote(text: "Eine einzelne Messung verändert deine Zielwerte nicht. Anpassungen basieren auf dem Trend über mehrere Wochen.")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Gewicht erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if value == nil, let last = entries.first {
                    value = (prefs.weightUnit.fromKg(last.kg) * 10).rounded() / 10
                }
                focused = true
            }
        }
    }

    private func save() {
        guard let kg, isValid else { return }
        LogService.logWeight(kg: kg, date: date, source: .manual, note: note.trimmingCharacters(in: .whitespaces), in: context)
        dismiss()
    }
}

// MARK: - Dashboard-Karte

struct WeightTrendCard: View {
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    private var trend: Double? {
        AdaptiveEnergyEstimator.weeklyTrend(entries.reversed().map { (date: $0.date, kg: $0.kg) }, days: 14)
    }

    var body: some View {
        NavigationLink(value: AppDestination.weight) {
            Card {
                CardHeader(title: "Gewichtstrend", symbol: "scalemass", tint: Theme.weight) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if let latest = entries.first {
                    HStack(alignment: .bottom, spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: 4) {
                            StatValue(value: Fmt.weight(latest.kg, unit: prefs.weightUnit), unit: prefs.weightUnit.symbol,
                                      label: Fmt.day(latest.date), valueFont: .metricMedium)
                            if let trend {
                                Label("\(Fmt.signed(prefs.weightUnit.fromKg(trend), digits: 2)) \(prefs.weightUnit.symbol) pro Woche",
                                      systemImage: abs(trend) < 0.05 ? "arrow.right" : (trend > 0 ? "arrow.up.right" : "arrow.down.right"))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if entries.count >= 3 {
                            ProgressWeightChart(entries: Array(entries.prefix(30).reversed()), unit: prefs.weightUnit,
                                                range: .all, compact: true)
                                .frame(width: 120, height: 54)
                        }
                    }
                } else {
                    Text("Noch keine Messung. Tippe, um dein Gewicht zu erfassen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
