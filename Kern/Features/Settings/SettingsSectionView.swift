import SwiftData
import SwiftUI

/// Detailansicht eines Einstellungsbereichs.
struct SettingsSectionView: View {
    let section: SettingsSection

    init(section: SettingsSection) {
        self.section = section
    }

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        Group {
            switch section {
            case .profile:
                if let profile = profiles.first { SettingsProfileForm(profile: profile) } else { missingProfile }
            case .goals:
                if let profile = profiles.first { SettingsGoalsForm(profile: profile) } else { missingProfile }
            case .targets:
                if let profile = profiles.first { SettingsTargetsForm(profile: profile) } else { missingProfile }
            case .modules: SettingsModulesForm()
            case .dashboard: SettingsDashboardForm(profile: profiles.first)
            case .units: SettingsUnitsForm()
            case .health: SettingsHealthForm()
            case .notifications: SettingsNotificationsForm()
            case .coach: SettingsCoachForm()
            case .privacy: SettingsPrivacyForm()
            case .auditLog: AuditLogView()
            case .tutorial: SettingsTutorialForm()
            case .about: SettingsAboutForm()
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var missingProfile: some View {
        ContentUnavailableView("Kein Profil", systemImage: "person.crop.circle.badge.questionmark",
                               description: Text("Schliesse zuerst die Einrichtung ab."))
    }
}

// MARK: - Gemeinsame Bausteine

/// Bearbeitbare Liste kurzer Begriffe (z. B. Allergien) als Chips.
struct SettingsTagEditor: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            if !items.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            items.removeAll { $0 == item }
                        } label: {
                            HStack(spacing: 4) {
                                Text(item).font(.subheadline)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item) entfernen")
                    }
                }
            }
            HStack {
                TextField(placeholder, text: $newItem)
                    .submitLabel(.done)
                    .onSubmit(add)
                if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Hinzufügen", action: add)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func add() {
        let parts = newItem.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for part in parts where !items.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            items.append(part)
        }
        newItem = ""
    }
}

/// Zeile mit Dezimalwert (nicht optional).
struct SettingsValueRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    var digits: Int = 1

    var body: some View {
        NumberField(title: title, value: Binding(get: { value }, set: { if let v = $0 { value = v } }),
                    unit: unit, fractionDigits: digits)
    }
}

/// Zeigt Sicherheitshinweise aus der Energieberechnung.
struct SettingsSafetyNotes: View {
    let notes: [SafetyNote]

    var body: some View {
        ForEach(notes) { note in
            Label {
                Text(note.text).font(.footnote)
            } icon: {
                Image(systemName: note.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                    .foregroundStyle(note.severity == .warning ? Theme.warning : .secondary)
            }
        }
    }
}

// MARK: - Profil

private struct SettingsProfileForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Bindable var profile: UserProfile

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { profile.birthDate ?? Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now },
            set: { profile.birthDate = $0 }
        )
    }

    private var hasBirthDate: Binding<Bool> {
        Binding(
            get: { profile.birthDate != nil },
            set: { on in
                profile.birthDate = on ? (profile.birthDate ?? Calendar.current.date(byAdding: .year, value: -30, to: .now)) : nil
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(get: { profile.heightCm }, set: { profile.heightCm = $0.clamped(100...250) })
    }

    private var startWeightBinding: Binding<Double> {
        Binding(get: { prefs.weightUnit.fromKg(profile.startWeightKg) },
                set: { profile.startWeightKg = prefs.weightUnit.toKg($0).clamped(25...350) })
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.displayName)
                    .textContentType(.name)
                Toggle("Geburtsdatum angeben", isOn: hasBirthDate)
                if profile.birthDate != nil {
                    DatePicker("Geburtsdatum", selection: birthDateBinding, in: ...Date.now, displayedComponents: .date)
                }
                SettingsValueRow(title: "Körpergrösse", value: heightBinding, unit: "cm", digits: 0)
                SettingsValueRow(title: "Startgewicht", value: startWeightBinding, unit: prefs.weightUnit.symbol)
                NumberField(title: "Körperfettanteil", value: $profile.bodyFatPercent, unit: "%")
            } header: {
                Text("Basisdaten")
            } footer: {
                Text("Der Körperfettanteil ist freiwillig. Ist er bekannt, kann Kern genauere Formeln verwenden.")
            }

            Section {
                Picker("Physiologische Angabe", selection: $profile.physiologicalSexRaw) {
                    ForEach(PhysiologicalSex.allCases) { Text($0.title).tag($0.rawValue) }
                }
                TextField("Geschlechtsidentität (optional)", text: $profile.genderIdentity)
            } header: {
                Text("Berechnungsgrundlage & Profil")
            } footer: {
                Text("Die physiologische Angabe wird nur für Energieformeln verwendet. Deine Geschlechtsidentität ist eine freiwillige Profilangabe und hat keinen Einfluss auf Funktionen oder Berechnungen.")
            }

            Section {
                Picker("Aktivitätsniveau", selection: $profile.activityLevelRaw) {
                    ForEach(ActivityLevel.allCases) { level in
                        VStack(alignment: .leading) {
                            Text(level.title)
                            Text(level.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(level.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)
                Picker("Besondere Situation", selection: $profile.specialSituationRaw) {
                    ForEach(SpecialSituation.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Alltag & Gesundheit")
            } footer: {
                if profile.specialSituation != .none {
                    Text("Für Schwangerschaft, Stillzeit und medizinische Begleitung gelten gesonderte Sicherheitsregeln – Kern berechnet dann z. B. kein Kaloriendefizit.")
                }
            }

            Section("Training") {
                Picker("Erfahrung", selection: $profile.trainingExperienceRaw) {
                    ForEach(TrainingExperience.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Stepper(value: $profile.trainingDaysPerWeek, in: 0...7) {
                    LabeledContent("Trainingstage pro Woche", value: "\(profile.trainingDaysPerWeek)")
                }
                Stepper(value: $profile.sessionDurationMin, in: 15...180, step: 15) {
                    LabeledContent("Dauer pro Einheit", value: "\(profile.sessionDurationMin) min")
                }
                Picker("Trainingsort", selection: $profile.trainingLocationRaw) {
                    ForEach(TrainingLocation.allCases) { Text($0.title).tag($0.rawValue) }
                }
                TextField("Stärken", text: $profile.strengths, axis: .vertical)
                TextField("Schwächen", text: $profile.weaknesses, axis: .vertical)
                SettingsTagEditor(title: "Bevorzugte Methoden", placeholder: "z. B. Supersätze", items: $profile.preferredMethods)
            }

            Section {
                TextField("Gewünschte Anpassungen", text: $profile.adaptationsNote, axis: .vertical)
                TextField("Bekannte Belastungsgrenzen", text: $profile.loadLimitsNote, axis: .vertical)
                TextField("Vorgaben von Fachpersonen", text: $profile.professionalGuidelines, axis: .vertical)
            } header: {
                Text("Angepasstes Training")
            } footer: {
                Text("Diese Angaben helfen bei der Übungsauswahl. Kern stellt keine Diagnosen und ersetzt keine ärztliche oder physiotherapeutische Behandlung.")
            }

            Section("Ernährung") {
                Picker("Ernährungsform", selection: $profile.dietTypeRaw) {
                    ForEach(DietType.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Stepper(value: $profile.mealsPerDay, in: 1...8) {
                    LabeledContent("Mahlzeiten pro Tag", value: "\(profile.mealsPerDay)")
                }
                Toggle("Interesse an Rezepten", isOn: $profile.wantsRecipes)
                SettingsTagEditor(title: "Allergien & Unverträglichkeiten", placeholder: "z. B. Laktose", items: $profile.allergies)
                SettingsTagEditor(title: "Esse ich nicht", placeholder: "z. B. Pilze", items: $profile.excludedFoods)
                SettingsTagEditor(title: "Esse ich gerne", placeholder: "z. B. Hüttenkäse", items: $profile.preferredFoods)
            }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        profile.updatedAt = .now
        ProfileService.recalculateTargets(for: profile, in: context)
        AuditLog.record(context, actor: .user, summary: "Profil aktualisiert", entityType: EntityType.profile,
                        entityID: profile.id.uuidString)
        context.saveQuietly()
        WidgetBridge.refresh(context: context)
    }
}

// MARK: - Ziele

private struct SettingsGoalsForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    let profile: UserProfile

    @Query(sort: \GoalPhase.startDate, order: .reverse) private var phases: [GoalPhase]

    @State private var selected: Set<FitnessGoal> = []
    @State private var primary: FitnessGoal = .healthierLife
    @State private var targetWeight: Double?
    @State private var rate: Double = 0.4
    @State private var adaptDashboard = true
    @State private var didLoad = false
    @State private var savedFeedback = false

    private var currentWeightKg: Double { ProfileService.latestWeightKg(in: context) ?? profile.startWeightKg }

    private var needsRate: Bool { primary == .loseWeight || primary == .gainWeight }

    private var rateRange: ClosedRange<Double> { primary == .gainWeight ? 0.1...0.5 : 0.1...1.0 }

    private var ratePercent: Double { currentWeightKg > 0 ? rate / currentWeightKg : 0 }

    var body: some View {
        Form {
            Section {
                ForEach(FitnessGoal.allCases) { goal in
                    Button {
                        toggle(goal)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: goal.symbol)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(goal.title).foregroundStyle(.primary)
                                Text(goal.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(goal) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected.contains(goal) ? .isSelected : [])
                }
            } header: {
                Text("Deine Ziele")
            } footer: {
                Text("Du kannst mehrere Ziele kombinieren. Das Hauptziel bestimmt Kalorienziel und Startseite.")
            }

            if selected.count > 1 {
                Section("Hauptziel") {
                    Picker("Hauptziel", selection: $primary) {
                        ForEach(FitnessGoal.allCases.filter { selected.contains($0) }) { Text($0.title).tag($0) }
                    }
                }
            }

            if selected.contains(.loseWeight) && selected.contains(.gainWeight) {
                Section {
                    InfoNote(text: "Abnehmen und Zunehmen widersprechen sich. Für die Berechnung zählt nur das Hauptziel.",
                             symbol: "exclamationmark.triangle", tint: Theme.warning)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if selected.contains(.rehabilitation) {
                Section {
                    InfoNote(text: "Medizinisch begleitetes Rehabilitationstraining wird erst nach fachlicher Prüfung angeboten. Bis dahin unterstützt Kern dich mit angepasstem Training auf Basis sicherer Regeln und deiner eigenen Angaben.",
                             symbol: "cross.case")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if primary.needsTargetWeight {
                Section {
                    NumberField(title: "Wunschgewicht", value: $targetWeight, unit: prefs.weightUnit.symbol)
                    if needsRate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Tempo")
                                Spacer()
                                Text("\(Fmt.decimal(prefs.weightUnit.fromKg(rate), maxDigits: 2)) \(prefs.weightUnit.symbol) pro Woche")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $rate, in: rateRange, step: 0.05)
                                .tint(Theme.accent)
                            Text("≈ \(Fmt.decimal(ratePercent * 100, maxDigits: 2)) % deines Körpergewichts pro Woche")
                                .font(.footnote)
                                .foregroundStyle(ratePercent > 0.01 ? Theme.warning : .secondary)
                        }
                    }
                } header: {
                    Text("Gewichtsziel")
                } footer: {
                    Text(primary == .loseWeight
                         ? "Gesundheitlich angemessen sind meist 0.25–0.75 % des Körpergewichts pro Woche. Mehr als 1 % begrenzt Kern automatisch."
                         : "Für eine Zunahme mit möglichst wenig Fett sind 0.1–0.3 kg pro Woche ein guter Richtwert.")
                }
            }

            Section {
                Toggle("Startseite an das Hauptziel anpassen", isOn: $adaptDashboard)
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        Text(savedFeedback ? "Gespeichert" : "Ziele speichern").fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(selected.isEmpty)
            } footer: {
                Text("Ein Zielwechsel beginnt eine neue Zielphase. Bisherige Einträge, Messwerte und deine Trainingshistorie bleiben vollständig erhalten und auswertbar.")
            }

            if !phases.isEmpty {
                Section("Bisherige Zielphasen") {
                    ForEach(phases) { phase in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(phase.primaryGoal.title)
                                if phase.isActive { Badge(text: "Aktiv", tint: Theme.accent) }
                            }
                            Text("\(Fmt.mediumDate(phase.startDate)) – \(phase.endDate.map(Fmt.mediumDate) ?? "heute") · \(Fmt.energyWithUnit(Double(phase.calorieTarget), unit: prefs.energyUnit))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: savedFeedback)
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        selected = Set(profile.goals)
        primary = profile.primaryGoal
        targetWeight = profile.targetWeightKg.map { prefs.weightUnit.fromKg($0) }
        rate = profile.weeklyRateKg.clamped(0.1...1.0)
    }

    private func toggle(_ goal: FitnessGoal) {
        if selected.contains(goal) {
            selected.remove(goal)
            if primary == goal, let next = selected.sorted(by: { $0.priority < $1.priority }).first { primary = next }
        } else {
            selected.insert(goal)
            if selected.count == 1 { primary = goal }
        }
    }

    private func save() {
        guard !selected.isEmpty else { return }
        if !selected.contains(primary), let first = selected.sorted(by: { $0.priority < $1.priority }).first { primary = first }
        rate = rate.clamped(rateRange)
        profile.targetWeightKg = targetWeight.map { prefs.weightUnit.toKg($0) }
        profile.weeklyRateKg = rate

        let goals = selected.sorted { $0.priority < $1.priority }
        if Set(profile.goals) != selected || profile.primaryGoal != primary {
            ProfileService.changeGoals(goals, primary: primary, for: profile, in: context)
        } else {
            ProfileService.recalculateTargets(for: profile, in: context)
            AuditLog.record(context, actor: .user, summary: "Gewichtsziel aktualisiert", entityType: EntityType.profile,
                            entityID: profile.id.uuidString)
            context.saveQuietly()
        }
        if adaptDashboard { prefs.dashboardCards = DashboardCardKind.defaults(for: primary) }
        WidgetBridge.refresh(context: context)
        savedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            savedFeedback = false
        }
    }
}

// MARK: - Zielwerte

private struct SettingsTargetsForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Bindable var profile: UserProfile

    private var inputs: EnergyInputs { ProfileService.energyInputs(for: profile, in: context) }

    private var result: EnergyResult {
        EnergyCalculator.compute(inputs, formula: profile.energyFormula, tdeeOverride: profile.adaptiveTDEE)
    }

    private var macroKcal: Int { profile.proteinTargetG * 4 + profile.carbTargetG * 4 + profile.fatTargetG * 9 }

    var body: some View {
        let result = self.result
        Form {
            Section {
                Picker("Formel", selection: $profile.energyFormulaRaw) {
                    ForEach(EnergyFormula.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Berechnung")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.energyFormula.detail)
                    if profile.energyFormula.needsBodyFat && profile.bodyFatPercent == nil {
                        Text("Ohne Körperfettanteil wird stattdessen Mifflin-St.-Jeor verwendet.")
                    }
                    if profile.energyFormula == .automatic {
                        Text("Aktuell verwendet: \(result.formula.title).")
                    }
                }
            }

            Section("Schätzung") {
                LabeledContent("Grundumsatz", value: Fmt.energyWithUnit(result.bmr, unit: prefs.energyUnit))
                LabeledContent("Gesamtbedarf", value: Fmt.energyWithUnit(result.tdee, unit: prefs.energyUnit))
                LabeledContent("Anpassung für dein Ziel", value: "\(Fmt.signed(result.adjustmentKcal, digits: 0)) kcal")
                LabeledContent("Berechnetes Tagesziel", value: Fmt.energyWithUnit(Double(result.calorieTarget), unit: prefs.energyUnit))
                DisclosureGroup("So wird gerechnet") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(result.explanation.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                SettingsSafetyNotes(notes: result.notes)
            }

            if let adaptive = profile.adaptiveTDEE {
                Section {
                    LabeledContent("Adaptive Schätzung", value: Fmt.energyWithUnit(adaptive, unit: prefs.energyUnit))
                    if let date = profile.adaptiveTDEEUpdatedAt {
                        LabeledContent("Übernommen am", value: Fmt.mediumDate(date))
                    }
                    NavigationLink(value: AppDestination.energyInsight) {
                        Text("Herleitung ansehen")
                    }
                    Button("Wieder Formelwert verwenden") {
                        profile.adaptiveTDEE = nil
                        profile.adaptiveTDEEUpdatedAt = nil
                        ProfileService.recalculateTargets(for: profile, in: context)
                        AuditLog.record(context, actor: .user, summary: "Adaptive Bedarfsschätzung zurückgesetzt", entityType: EntityType.profile)
                        context.saveQuietly()
                    }
                } header: {
                    Text("Aus deinen Verlaufsdaten")
                } footer: {
                    Text("Kern verfeinert die Schätzung anhand deines Gewichtsverlaufs und deiner erfassten Kalorien. Änderungen werden dir immer zur Bestätigung vorgeschlagen.")
                }
            }

            Section {
                Toggle("Eigene Zielwerte festlegen", isOn: Binding(
                    get: { profile.targetsAreManual },
                    set: { manual in
                        profile.targetsAreManual = manual
                        if !manual { ProfileService.apply(result, to: profile) }
                    }
                ))
                if profile.targetsAreManual {
                    Stepper(value: $profile.calorieTarget, in: EnergyCalculator.minimumAllowedTarget(for: inputs)...6000, step: 50) {
                        LabeledContent("Kalorien", value: Fmt.energyWithUnit(Double(profile.calorieTarget), unit: prefs.energyUnit))
                    }
                    macroStepper("Protein", value: $profile.proteinTargetG, range: 30...400)
                    macroStepper("Kohlenhydrate", value: $profile.carbTargetG, range: 20...800)
                    macroStepper("Fett", value: $profile.fatTargetG, range: 20...300)
                    macroStepper("Ballaststoffe", value: $profile.fiberTargetG, range: 10...80)
                    LabeledContent("Summe aus Makros", value: "\(Fmt.number(Double(macroKcal))) kcal")
                        .foregroundStyle(abs(macroKcal - profile.calorieTarget) > 150 ? Theme.warning : .secondary)
                    SettingsSafetyNotes(notes: EnergyCalculator.validateManualTarget(kcal: profile.calorieTarget, inputs: inputs))
                } else {
                    LabeledContent("Kalorien", value: Fmt.energyWithUnit(Double(profile.calorieTarget), unit: prefs.energyUnit))
                    LabeledContent("Protein", value: "\(profile.proteinTargetG) g")
                    LabeledContent("Kohlenhydrate", value: "\(profile.carbTargetG) g")
                    LabeledContent("Fett", value: "\(profile.fatTargetG) g")
                    LabeledContent("Ballaststoffe", value: "\(profile.fiberTargetG) g")
                }
            } header: {
                Text("Tagesziele")
            } footer: {
                Text(profile.targetsAreManual
                     ? "Manuelle Werte werden nicht automatisch überschrieben. Ungeeignete Werte markiert Kern mit einem Hinweis."
                     : "Die Werte passen sich automatisch an, wenn sich Gewicht, Ziel oder Formel ändern.")
            }

            Section("Weitere Ziele") {
                Stepper(value: $profile.waterTargetMl, in: 1000...6000, step: 100) {
                    LabeledContent("Trinkziel", value: Fmt.volume(Double(profile.waterTargetMl)))
                }
                Stepper(value: $profile.stepsTarget, in: 1000...30000, step: 500) {
                    LabeledContent("Schritte pro Tag", value: Fmt.number(Double(profile.stepsTarget)))
                }
                Stepper(value: $profile.weeklyWorkoutTarget, in: 0...14) {
                    LabeledContent("Trainings pro Woche", value: "\(profile.weeklyWorkoutTarget)")
                }
            }
        }
        .onChange(of: profile.energyFormulaRaw) { _, _ in
            ProfileService.recalculateTargets(for: profile, in: context)
        }
        .onDisappear {
            profile.updatedAt = .now
            AuditLog.record(context, actor: .user, summary: "Zielwerte aktualisiert",
                            detail: "\(profile.calorieTarget) kcal · \(profile.proteinTargetG) g Protein",
                            entityType: EntityType.profile, entityID: profile.id.uuidString)
            context.saveQuietly()
            WidgetBridge.refresh(context: context)
        }
    }

    private func macroStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 5) {
            LabeledContent(title, value: "\(value.wrappedValue) g")
        }
    }
}
