import SwiftUI
import SwiftData

/// Erklärt die Bedarfsberechnung und schlägt adaptive Anpassungen vor,
/// die der Nutzer annehmen, ablehnen oder manuell verändern kann.
struct EnergyInsightView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Query private var profiles: [UserProfile]

    @AppStorage("kern.energy.dismissedEstimate") private var dismissedEstimate: Double = 0
    @State private var estimate: AdaptiveEstimate?
    @State private var loggedDays = 0
    @State private var weighIns = 0
    @State private var hasLoaded = false
    @State private var confirmation: String?

    var body: some View {
        Group {
            if let profile = profiles.first {
                content(profile)
            } else {
                ContentUnavailableView("Kein Profil", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Energiebedarf")
        .task { load() }
    }

    private func content(_ profile: UserProfile) -> some View {
        let inputs = ProfileService.energyInputs(for: profile, in: context)
        let formulaResult = EnergyCalculator.compute(inputs, formula: profile.energyFormula)
        let activeResult = EnergyCalculator.compute(inputs, formula: profile.energyFormula, tdeeOverride: profile.adaptiveTDEE)
        let currentTDEE = profile.adaptiveTDEE ?? formulaResult.tdee

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Card {
                    CardHeader(title: "Geschätzter Gesamtbedarf", symbol: "flame", tint: Theme.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.energy(currentTDEE, unit: prefs.energyUnit))
                            .font(.metricLarge)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(prefs.energyUnit.symbol)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(profile.adaptiveTDEE != nil
                         ? "Adaptiv aus deinen Verlaufsdaten (übernommen \(profile.adaptiveTDEEUpdatedAt.map(Fmt.mediumDate) ?? "–"))"
                         : "Aus der Formel \(formulaResult.formula.title)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.l) {
                        StatValue(value: Fmt.energy(formulaResult.bmr, unit: prefs.energyUnit), unit: prefs.energyUnit.symbol, label: "Grundumsatz")
                        StatValue(value: Fmt.energy(Double(profile.calorieTarget), unit: prefs.energyUnit), unit: prefs.energyUnit.symbol, label: "Tagesziel")
                    }
                    .padding(.top, Theme.Space.xxs)
                }

                if let confirmation {
                    InfoNote(text: confirmation, symbol: "checkmark.circle", tint: Theme.positive)
                }

                proposalSection(profile: profile, formulaTDEE: formulaResult.tdee, currentTDEE: currentTDEE)

                SectionTitle(title: "So wird gerechnet")
                Card {
                    ForEach(Array(activeResult.explanation.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20, height: 20)
                                .background(Theme.accent.opacity(0.12), in: Circle())
                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                    Text(formulaResult.formula.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if profile.targetsAreManual {
                    InfoNote(text: "Deine Zielwerte sind manuell festgelegt und werden nicht automatisch überschrieben.",
                             symbol: "hand.raised")
                }

                ForEach(activeResult.notes) { note in
                    InfoNote(text: note.text,
                             symbol: note.severity == .warning ? "exclamationmark.triangle" : "info.circle",
                             tint: note.severity == .warning ? Theme.warning : .secondary)
                }

                SectionTitle(title: "Datengrundlage")
                Card {
                    MetricRow(label: "Vollständig erfasste Tage (28)", value: Double(loggedDays),
                              target: Double(AdaptiveEnergyEstimator.minimumLoggedDays), unit: "Tage", tint: Theme.accent)
                    MetricRow(label: "Wägungen (28 Tage)", value: Double(weighIns),
                              target: Double(AdaptiveEnergyEstimator.minimumWeighIns), unit: "", tint: Theme.weight)
                    Text("Die adaptive Schätzung braucht mindestens \(AdaptiveEnergyEstimator.minimumLoggedDays) vollständig erfasste Tage und \(AdaptiveEnergyEstimator.minimumWeighIns) Wägungen über zwei Wochen. Einzelne Messungen lösen nie eine Änderung aus.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                NavigationLink(value: AppDestination.settingsSection(.targets)) {
                    Label("Ziele manuell anpassen", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func proposalSection(profile: UserProfile, formulaTDEE: Double, currentTDEE: Double) -> some View {
        if let estimate {
            let differs = abs(estimate.tdee - currentTDEE) >= 50
            let dismissed = abs(dismissedEstimate - estimate.tdee) < 1
            Card {
                CardHeader(title: "Adaptive Schätzung", symbol: "waveform.path.ecg", tint: Theme.weight) {
                    Badge(text: "Sicherheit \(Fmt.percent(estimate.confidence))", tint: estimate.isReliable ? Theme.positive : Theme.warning)
                }
                Text(estimate.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if estimate.isReliable && differs && !dismissed {
                    Divider()
                    Text("Neue Schätzung übernehmen?")
                        .font(.headline)
                    Text("Gesamtbedarf \(Fmt.number(currentTDEE)) → \(Fmt.number(estimate.tdee)) kcal (\(Fmt.signed(estimate.tdee - currentTDEE, digits: 0)) kcal). Deine Ziele werden entsprechend neu berechnet\(profile.targetsAreManual ? ", sofern sie nicht manuell festgelegt sind" : "").")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.s) {
                        Button("Ablehnen") {
                            dismissedEstimate = estimate.tdee
                            AuditLog.record(context, actor: .user, summary: "Adaptive Bedarfsschätzung abgelehnt (\(Fmt.number(estimate.tdee)) kcal)",
                                            entityType: EntityType.profile)
                            context.saveQuietly()
                        }
                        .buttonStyle(.glass)
                        Button("Annehmen") { accept(estimate, profile: profile) }
                            .buttonStyle(.glassProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else if !estimate.isReliable {
                    InfoNote(text: "Die Datensicherheit ist noch zu gering für einen Vorschlag. Erfasse weiter möglichst vollständig.")
                } else if !differs {
                    Text("Die Schätzung entspricht deinem aktuellen Bedarf – keine Anpassung nötig.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if profile.adaptiveTDEE != nil {
                    Button("Wieder Formelwert verwenden (\(Fmt.number(formulaTDEE)) kcal)") { resetToFormula(profile) }
                        .font(.footnote.weight(.medium))
                }
            }
        } else if hasLoaded {
            Card {
                CardHeader(title: "Adaptive Schätzung", symbol: "waveform.path.ecg", tint: Theme.weight)
                Text("Noch nicht genug Daten. Sobald du rund zwei Wochen Ernährung und Gewicht erfasst hast, verfeinert Kern die Formel-Schätzung mit deinen tatsächlichen Werten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if profile.adaptiveTDEE != nil {
                    Button("Wieder Formelwert verwenden (\(Fmt.number(formulaTDEE)) kcal)") { resetToFormula(profile) }
                        .font(.footnote.weight(.medium))
                }
            }
        }
    }

    private func load() {
        guard let profile = profiles.first else { return }
        let intake = ProgressData.intakeByDay(in: context, days: 28)
        let weights = ProgressData.weightPoints(in: context)
        let windowStart = Date.now.adding(days: -28).startOfDay
        loggedDays = DayKey.range(endingAt: Date.now.adding(days: -1), count: 28)
            .compactMap { intake[$0] }
            .filter { $0 >= AdaptiveEnergyEstimator.minimumDayKcal }.count
        weighIns = weights.filter { $0.date >= windowStart }.count
        let formula = EnergyCalculator.compute(ProfileService.energyInputs(for: profile, in: context), formula: profile.energyFormula)
        estimate = AdaptiveEnergyEstimator.estimate(intakeByDay: intake, weights: weights, formulaTDEE: formula.tdee,
                                                    previous: profile.adaptiveTDEE)
        hasLoaded = true
    }

    private func accept(_ estimate: AdaptiveEstimate, profile: UserProfile) {
        let previous = profile.adaptiveTDEE
        profile.adaptiveTDEE = estimate.tdee
        profile.adaptiveTDEEUpdatedAt = .now
        ProfileService.recalculateTargets(for: profile, in: context)
        AuditLog.record(context, actor: .user,
                        summary: "Adaptive Bedarfsschätzung übernommen: \(Fmt.number(estimate.tdee)) kcal",
                        detail: "Vorher: \(previous.map { Fmt.number($0) } ?? "Formelwert"), Sicherheit \(Fmt.percent(estimate.confidence))",
                        entityType: EntityType.profile, entityID: profile.id.uuidString)
        context.saveQuietly()
        withAnimation(.smooth) {
            confirmation = profile.targetsAreManual
                ? "Schätzung übernommen. Deine manuellen Ziele bleiben unverändert."
                : "Schätzung übernommen. Neues Tagesziel: \(Fmt.number(Double(profile.calorieTarget))) kcal."
        }
    }

    private func resetToFormula(_ profile: UserProfile) {
        profile.adaptiveTDEE = nil
        profile.adaptiveTDEEUpdatedAt = nil
        ProfileService.recalculateTargets(for: profile, in: context)
        AuditLog.record(context, actor: .user, summary: "Adaptive Bedarfsschätzung zurückgesetzt", entityType: EntityType.profile)
        context.saveQuietly()
        withAnimation(.smooth) { confirmation = "Es wird wieder der Formelwert verwendet." }
    }
}
