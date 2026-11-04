import SwiftUI
import SwiftData
import Charts

/// Tab „Fortschritt“: Gewicht, gemeinsame Fortschrittslogik, Analysen und Körperentwicklung.
struct ProgressHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \GoalPhase.startDate, order: .reverse) private var phases: [GoalPhase]

    @State private var range: ProgressRange = .quarter
    @State private var summary: ProgressCombinedSummary?
    @State private var exportURL: URL?

    private var profile: UserProfile? { profiles.first }
    private var activePhase: GoalPhase? { phases.first { $0.isActive } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                weightCard
                combinedCard
                analysisLinks
                if hasBodyModules { bodyLinks }
                if !phases.isEmpty { phaseTimeline }
                exportCard
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .navigationTitle("Fortschritt")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { router.present(.weightEntry) } label: { Label("Gewicht erfassen", systemImage: "scalemass") }
                    if prefs.isEnabled(.measurements) {
                        Button { router.present(.measurementEntry) } label: { Label("Körpermasse erfassen", systemImage: "ruler") }
                    }
                } label: {
                    Label("Erfassen", systemImage: "plus")
                }
            }
        }
        .task(id: weights.count) { refresh() }
    }

    // MARK: Gewicht

    private var weightCard: some View {
        Card {
            CardHeader(title: "Gewicht", symbol: "scalemass", tint: Theme.weight) {
                NavigationLink(value: AppDestination.weight) {
                    Text("Alle").font(.subheadline.weight(.medium))
                }
            }
            if weights.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Noch kein Gewicht erfasst.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Erste Messung erfassen") { router.present(.weightEntry) }
                        .buttonStyle(.glassProminent)
                }
            } else {
                stats
                Picker("Zeitraum", selection: $range) {
                    ForEach(ProgressRange.allCases) { r in
                        Text(r.title).tag(r).accessibilityLabel(r.accessibilityTitle)
                    }
                }
                .pickerStyle(.segmented)
                if weights.count >= 2 {
                    ProgressWeightChart(entries: weights, unit: prefs.weightUnit, range: range)
                        .frame(height: 200)
                }
                HStack(spacing: Theme.Space.m) {
                    legendDot(Theme.weight.opacity(0.35), "Messungen")
                    legendDot(Theme.weight, "Geglätteter Trend")
                }
            }
        }
    }

    private var stats: some View {
        let unit = prefs.weightUnit
        let latest = weights.last
        let start = activePhase?.startWeightKg ?? profile?.startWeightKg
        let trend = AdaptiveEnergyEstimator.weeklyTrend(weights.map { (date: $0.date, kg: $0.kg) })
        return HStack(alignment: .top) {
            if let latest {
                StatValue(value: Fmt.weight(latest.kg, unit: unit), unit: unit.symbol, label: "Aktuell", valueFont: .metricMedium)
            }
            Spacer()
            if let latest, let start {
                StatValue(value: Fmt.signed(unit.fromKg(latest.kg - start), digits: 1), unit: unit.symbol,
                          label: activePhase != nil ? "Seit Zielbeginn" : "Seit Start")
            }
            Spacer()
            StatValue(value: trend.map { Fmt.signed(unit.fromKg($0), digits: 2) } ?? "–", unit: trend == nil ? nil : unit.symbol,
                      label: "Pro Woche")
        }
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Gemeinsame Fortschrittslogik

    private var combinedCard: some View {
        Card {
            CardHeader(title: "Letzte 4 Wochen im Zusammenhang", symbol: "point.3.connected.trianglepath.dotted", tint: Theme.accent)
            if let summary {
                Text(summary.statement)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top) {
                    StatValue(value: summary.averageIntake.map { Fmt.energy($0, unit: prefs.energyUnit) } ?? "–",
                              unit: summary.averageIntake == nil ? nil : prefs.energyUnit.symbol, label: "Ø Aufnahme")
                    Spacer()
                    StatValue(value: summary.weightTrendPerWeek.map { Fmt.signed(prefs.weightUnit.fromKg($0), digits: 2) } ?? "–",
                              unit: summary.weightTrendPerWeek == nil ? nil : prefs.weightUnit.symbol, label: "Gewicht/Woche")
                    Spacer()
                    StatValue(value: "\(summary.improvedLifts.count)", label: "Übungen besser")
                    Spacer()
                    StatValue(value: "\(summary.sessions)", label: "Trainings")
                }
                Text("Beobachtete Zusammenhänge, keine belegten Ursachen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Wird berechnet …").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Links

    private var analysisLinks: some View {
        Card {
            ProgressLinkRow(title: "Wochenanalyse", subtitle: "Was diese Woche passiert ist", symbol: "text.magnifyingglass",
                            tint: Theme.accent, destination: .weeklyReport)
            Divider()
            ProgressLinkRow(title: "Energiebedarf", subtitle: "Formel und adaptive Schätzung", symbol: "flame",
                            tint: Theme.training, destination: .energyInsight)
            Divider()
            ProgressLinkRow(title: "Gewichtsverlauf", subtitle: "\(weights.count) Messungen", symbol: "scalemass",
                            tint: Theme.weight, destination: .weight)
        }
    }

    private var hasBodyModules: Bool {
        prefs.isEnabled(.measurements) || prefs.isEnabled(.bodyAvatar) || prefs.isEnabled(.progressPhotos)
    }

    private var bodyLinks: some View {
        Card {
            let rows: [(String, String, String, AppDestination, AppModule)] = [
                ("Körpermasse", "Umfänge und Körperfett", "ruler", .measurements, .measurements),
                ("3D-Körper", "Illustrative Darstellung", "figure.stand", .bodyAvatar, .bodyAvatar),
                ("Fortschrittsfotos", "Privat auf diesem Gerät", "photo.on.rectangle", .progressPhotos, .progressPhotos)
            ]
            let visible = rows.filter { prefs.isEnabled($0.4) }
            ForEach(Array(visible.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                ProgressLinkRow(title: row.0, subtitle: row.1, symbol: row.2, tint: Theme.weight, destination: row.3)
            }
        }
    }

    // MARK: Zielphasen

    private var phaseTimeline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Zielphasen")
            Card {
                ForEach(Array(phases.prefix(6).enumerated()), id: \.element.id) { index, phase in
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(phase.isActive ? Theme.accent : Theme.fillStrong)
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                            if index < min(phases.count, 6) - 1 {
                                Rectangle().fill(Theme.fill).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: phase.primaryGoal.symbol).font(.footnote)
                                Text(phase.primaryGoal.title).font(.subheadline.weight(.semibold))
                                if phase.isActive { Badge(text: "Aktiv", tint: Theme.accent) }
                            }
                            Text(phaseDates(phase))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(phaseDetail(phase))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, Theme.Space.s)
                        Spacer(minLength: 0)
                    }
                }
                Text("Zielwechsel löschen keine Daten – frühere Phasen bleiben auswertbar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func phaseDates(_ phase: GoalPhase) -> String {
        let end = phase.endDate.map(Fmt.mediumDate) ?? "heute"
        return "\(Fmt.mediumDate(phase.startDate)) – \(end)"
    }

    private func phaseDetail(_ phase: GoalPhase) -> String {
        var parts = ["\(Fmt.number(Double(phase.calorieTarget))) kcal"]
        let phaseEnd = phase.endDate ?? .now
        let inPhase = weights.filter { $0.date >= phase.startDate && $0.date <= phaseEnd }
        if let first = inPhase.first, let last = inPhase.last, inPhase.count >= 2 {
            parts.append("\(Fmt.signed(prefs.weightUnit.fromKg(last.kg - first.kg), digits: 1)) \(prefs.weightUnit.symbol)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Export

    private var exportCard: some View {
        Card {
            CardHeader(title: "Fortschrittsbericht", symbol: "doc.text")
            Text("Exportiere eine Übersicht deiner Entwicklung als Text oder deine Gewichtsdaten als CSV.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.s) {
                ShareLink(item: reportText) {
                    Label("Bericht", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("CSV", systemImage: "tablecells")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var reportText: String {
        let unit = prefs.weightUnit
        var lines = ["Kern – Fortschrittsbericht", "Erstellt am \(Fmt.mediumDate(.now))", ""]
        if let profile {
            lines.append("Ziel: \(profile.goals.map(\.title).joined(separator: ", ").isEmpty ? profile.primaryGoal.title : profile.goals.map(\.title).joined(separator: ", "))")
            lines.append("Tagesziel: \(Fmt.number(Double(profile.calorieTarget))) kcal · Protein \(profile.proteinTargetG) g")
        }
        if let first = weights.first, let last = weights.last {
            lines.append("Gewicht: \(Fmt.weightWithUnit(first.kg, unit: unit)) (\(Fmt.mediumDate(first.date))) → \(Fmt.weightWithUnit(last.kg, unit: unit)) (\(Fmt.mediumDate(last.date)))")
        }
        if let summary {
            lines.append("")
            lines.append("Letzte 4 Wochen: \(summary.statement)")
        }
        if !phases.isEmpty {
            lines.append("")
            lines.append("Zielphasen:")
            for phase in phases {
                lines.append("• \(phase.primaryGoal.title): \(phaseDates(phase)) – \(phaseDetail(phase))")
            }
        }
        lines.append("")
        lines.append("Hinweis: Beobachtete Zusammenhänge sind keine belegten Ursachen. Keine medizinische Bewertung.")
        return lines.joined(separator: "\n")
    }

    private func refresh() {
        if let profile {
            summary = InsightEngine.combinedSummary(in: context, profile: profile)
        }
        exportURL = writeCSV()
    }

    private func writeCSV() -> URL? {
        guard !weights.isEmpty else { return nil }
        var csv = "datum;uhrzeit;gewicht_kg;quelle;notiz\n"
        for w in weights {
            let note = w.note.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ")
            csv += "\(DayKey.make(w.date));\(Fmt.time(w.date));\(String(format: "%.2f", w.kg));\(w.source.rawValue);\(note)\n"
        }
        let url = URL.temporaryDirectory.appending(path: "Kern-Gewicht.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
