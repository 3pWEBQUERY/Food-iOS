import SwiftUI
import SwiftData

/// Darstellung einer einzelnen Aussage mit ihrer Art (Beobachtung, Schätzung …).
struct ProgressInsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: insight.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(insight.kind.tint)
                .frame(width: 32, height: 32)
                .background(insight.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.kind.title.uppercased())
                    .font(.caption2Strong)
                    .foregroundStyle(insight.kind.tint)
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                Text(insight.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WeeklyReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query private var profiles: [UserProfile]

    @State private var weekOffset = 0
    @State private var report: WeeklyReport?
    @State private var months: [ProgressMonthSummary] = []

    private var referenceDate: Date { Date.now.adding(days: -7 * weekOffset) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                weekSwitcher

                if let report {
                    Card {
                        Text(report.periodTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(report.headline)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Card {
                        ForEach(Array(report.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            ProgressInsightRow(insight: item)
                        }
                    }

                    InfoNote(text: "Beobachtungen beschreiben zeitliche Zusammenhänge in deinen Daten. Schätzungen sind mit Unsicherheit verbunden. Ursachen lassen sich daraus nicht sicher ableiten.")
                }

                if !months.isEmpty {
                    SectionTitle(title: "Monatsvergleich")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                                if index > 0 { Divider().padding(.leading, Theme.Space.m) }
                                monthRow(month)
                            }
                        }
                    }
                    yearComparison
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .navigationTitle("Wochenanalyse")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let report {
                    ShareLink(item: InsightEngine.reportText(report)) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: weekOffset) { load() }
    }

    private var weekSwitcher: some View {
        HStack {
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Vorherige Woche")
            Spacer()
            Text(weekOffset == 0 ? "Diese Woche" : weekOffset == 1 ? "Letzte Woche" : "Vor \(weekOffset) Wochen")
                .font(.headline)
            Spacer()
            Button { weekOffset = max(0, weekOffset - 1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .disabled(weekOffset == 0)
            .accessibilityLabel("Nächste Woche")
        }
    }

    private func monthRow(_ month: ProgressMonthSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.title).font(.subheadline.weight(.medium))
                Text("\(month.loggedDays) Tage erfasst · \(month.sessions) Trainings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(month.averageWeightKg.map { Fmt.weightWithUnit($0, unit: prefs.weightUnit) } ?? "–")
                    .font(.subheadline.monospacedDigit())
                Text(month.averageIntake.map { "Ø \(Fmt.energyWithUnit($0, unit: prefs.energyUnit))" } ?? "–")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var yearComparison: some View {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: .now)
        let weights = ProgressData.weights(in: context)
        let current = weights.filter { cal.component(.year, from: $0.date) == thisYear }.map(\.kg)
        let last = weights.filter { cal.component(.year, from: $0.date) == thisYear - 1 }.map(\.kg)
        if !current.isEmpty {
            Card {
                CardHeader(title: "Jahresvergleich Gewicht", symbol: "calendar")
                HStack {
                    StatValue(value: Fmt.weight(current.reduce(0, +) / Double(current.count), unit: prefs.weightUnit),
                              unit: prefs.weightUnit.symbol, label: "Ø \(thisYear)")
                    Spacer()
                    if !last.isEmpty {
                        StatValue(value: Fmt.weight(last.reduce(0, +) / Double(last.count), unit: prefs.weightUnit),
                                  unit: prefs.weightUnit.symbol, label: "Ø \(thisYear - 1)")
                    } else {
                        Text("Keine Daten aus \(thisYear - 1)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func load() {
        guard let profile = profiles.first else { return }
        report = InsightEngine.weeklyReport(in: context, profile: profile, now: referenceDate)
        if months.isEmpty {
            months = InsightEngine.monthlySummaries(in: context, months: 12)
                .filter { $0.loggedDays > 0 || $0.sessions > 0 || $0.averageWeightKg != nil }
        }
    }
}

// MARK: - Dashboard-Karte

struct WeeklyInsightCard: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var report: WeeklyReport?

    var body: some View {
        NavigationLink(value: AppDestination.weeklyReport) {
            Card {
                CardHeader(title: "Wochenanalyse", symbol: "text.magnifyingglass", tint: Theme.accent) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if let report {
                    Text(report.headline)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(report.items.prefix(2)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: item.symbol)
                                .font(.footnote)
                                .foregroundStyle(item.kind.tint)
                                .frame(width: 18)
                            Text(item.title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Wird berechnet …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            if let profile = profiles.first {
                report = InsightEngine.weeklyReport(in: context, profile: profile)
            }
        }
    }
}
