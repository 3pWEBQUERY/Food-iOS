import SwiftUI
import SwiftData
import Charts

/// Messpunkt inkl. Körperfett für generische Darstellung.
private struct ProgressMeasureField: Identifiable, Hashable {
    let key: String
    let title: String
    let unit: String
    var id: String { key }

    static let all: [ProgressMeasureField] =
        BodyMeasurement.fields.map { ProgressMeasureField(key: $0.key, title: $0.title, unit: "cm") }
        + [ProgressMeasureField(key: "bodyFatPercent", title: "Körperfett", unit: "%")]
}

// MARK: - Übersicht

struct MeasurementsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @State private var selectedKey = "waistCm"

    private var selectedField: ProgressMeasureField {
        ProgressMeasureField.all.first { $0.key == selectedKey } ?? ProgressMeasureField.all[0]
    }

    private func series(_ key: String) -> [ProgressChartPoint] {
        measurements.compactMap { m in m.value(for: key).map { ProgressChartPoint(date: m.date, value: $0) } }
    }

    var body: some View {
        List {
            if measurements.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Noch keine Körpermasse", systemImage: "ruler")
                    } description: {
                        Text("Erfasse nur, was du tatsächlich misst – alle Werte sind optional.")
                    } actions: {
                        Button("Erste Messung erfassen") { router.present(.measurementEntry) }
                            .buttonStyle(.glassProminent)
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Picker("Messpunkt", selection: $selectedKey) {
                            ForEach(ProgressMeasureField.all) { field in
                                Text(field.title).tag(field.key)
                            }
                        }
                        .pickerStyle(.menu)

                        let points = series(selectedKey)
                        if points.count >= 2 {
                            Chart(points) { point in
                                LineMark(x: .value("Datum", point.date), y: .value(selectedField.title, point.value))
                                    .foregroundStyle(Theme.weight)
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Datum", point.date), y: .value(selectedField.title, point.value))
                                    .foregroundStyle(Theme.weight)
                                    .symbolSize(28)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 180)
                            .accessibilityLabel("Verlauf \(selectedField.title)")
                        } else {
                            Text(points.isEmpty ? "Für \(selectedField.title) gibt es noch keine Messung." : "Ab zwei Messungen erscheint hier ein Verlauf.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }

                Section("Aktuell") {
                    ForEach(ProgressMeasureField.all) { field in
                        let points = series(field.key)
                        if let last = points.last {
                            HStack {
                                Text(field.title)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Fmt.decimal(last.value)) \(field.unit)")
                                        .font(.body.monospacedDigit())
                                    if points.count >= 2, let first = points.first {
                                        let previous = points[points.count - 2]
                                        Text("\(Fmt.signed(last.value - previous.value)) zur letzten · \(Fmt.signed(last.value - first.value)) gesamt")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedKey = field.key }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("Verlauf") {
                    ForEach(measurements.reversed()) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Fmt.mediumDate(m.date)).font(.subheadline.weight(.medium))
                            Text(summary(m))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(m) } label: { Label("Löschen", systemImage: "trash") }
                        }
                    }
                }
            }

            Section {
                InfoNote(text: "Miss möglichst zur gleichen Tageszeit, am besten morgens, mit lockerem Massband direkt auf der Haut.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Körpermasse")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { router.present(.measurementEntry) } label: {
                    Label("Messung erfassen", systemImage: "plus")
                }
            }
        }
    }

    private func summary(_ m: BodyMeasurement) -> String {
        ProgressMeasureField.all.compactMap { field in
            m.value(for: field.key).map { "\(field.title) \(Fmt.decimal($0)) \(field.unit)" }
        }.joined(separator: " · ")
    }

    private func delete(_ m: BodyMeasurement) {
        AuditLog.record(context, actor: .user, summary: "Körpermessung vom \(Fmt.shortDate(m.date)) gelöscht",
                        entityType: EntityType.measurement, entityID: m.id.uuidString)
        context.delete(m)
        context.saveQuietly()
    }
}

// MARK: - Erfassen

struct MeasurementEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var previous: [BodyMeasurement]

    @State private var values: [String: Double] = [:]
    @State private var date: Date = .now
    @State private var note = ""
    @State private var updateProfileBodyFat = true

    private func binding(_ key: String) -> Binding<Double?> {
        Binding(get: { values[key] }, set: { values[key] = $0 })
    }

    private var hasValues: Bool { !values.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    ForEach(ProgressMeasureField.all.filter { $0.unit == "cm" }) { field in
                        NumberField(title: field.title, value: binding(field.key), unit: "cm")
                    }
                } header: {
                    Text("Umfänge")
                } footer: {
                    if let last = previous.first {
                        Text("Letzte Messung: \(Fmt.mediumDate(last.date)). Leere Felder werden nicht gespeichert.")
                    } else {
                        Text("Leere Felder werden nicht gespeichert.")
                    }
                }
                Section {
                    NumberField(title: "Körperfett", value: binding("bodyFatPercent"), unit: "%")
                    if values["bodyFatPercent"] != nil {
                        Toggle("Im Profil für Berechnungen verwenden", isOn: $updateProfileBodyFat)
                    }
                } footer: {
                    Text("Messmethoden (Waage, Caliper, DEXA) liefern unterschiedliche Werte. Vergleiche möglichst mit derselben Methode.")
                }
                Section {
                    TextField("Notiz (optional)", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Körpermasse erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).disabled(!hasValues)
                }
            }
        }
    }

    private func save() {
        let measurement = BodyMeasurement(date: date)
        for (key, value) in values where value > 0 {
            measurement.setValue(value, for: key)
        }
        measurement.note = note
        context.insert(measurement)
        if updateProfileBodyFat, let bf = values["bodyFatPercent"], (3...70).contains(bf), let profile = profiles.first {
            profile.bodyFatPercent = bf
            ProfileService.recalculateTargets(for: profile, in: context)
        }
        AuditLog.record(context, actor: .user, summary: "Körpermasse erfasst (\(values.count) Werte)",
                        entityType: EntityType.measurement, entityID: measurement.id.uuidString, undoable: true)
        context.saveQuietly()
        dismiss()
    }
}

// MARK: - Dashboard-Karte

struct MeasurementsCard: View {
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]

    private func latestAndDelta(_ key: String) -> (Double, Double?)? {
        let values = measurements.compactMap { $0.value(for: key) }
        guard let last = values.last else { return nil }
        return (last, values.count >= 2 ? last - values[0] : nil)
    }

    var body: some View {
        NavigationLink(value: AppDestination.measurements) {
            Card {
                CardHeader(title: "Körpermasse", symbol: "ruler", tint: Theme.weight) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if measurements.isEmpty {
                    Text("Noch keine Messung erfasst.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: Theme.Space.l) {
                        cell("Taille", key: "waistCm", unit: "cm")
                        cell("Hüfte", key: "hipCm", unit: "cm")
                        cell("Körperfett", key: "bodyFatPercent", unit: "%")
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cell(_ title: String, key: String, unit: String) -> some View {
        if let result = latestAndDelta(key) {
            VStack(alignment: .leading, spacing: 2) {
                StatValue(value: Fmt.decimal(result.0), unit: unit, label: title)
                if let delta = result.1 {
                    Text("\(Fmt.signed(delta)) gesamt")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
