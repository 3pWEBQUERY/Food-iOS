import SwiftUI

// MARK: - Ziele

struct OnboardingGoalsStep: View {
    @Bindable var model: OnboardingModel

    private let mainGoals: [FitnessGoal] = [.loseWeight, .buildMuscle, .recomposition, .maintain, .gainWeight]
    private let moreGoals: [FitnessGoal] = [.fitness, .strengthEndurance, .healthierLife, .trackOnly, .adaptedTraining, .rehabilitation]

    var body: some View {
        OnboardingPage(title: "Was möchtest du erreichen?",
                       subtitle: "Wähle eines oder mehrere Ziele. Du kannst sie jederzeit ändern – deine Daten bleiben erhalten.") {
            VStack(spacing: Theme.Space.xs) {
                ForEach(mainGoals) { goal in option(goal) }
            }
            Text("Weitere Ziele")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Space.xs)
            VStack(spacing: Theme.Space.xs) {
                ForEach(moreGoals) { goal in option(goal) }
            }

            if model.goals.count > 1 {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Wichtigstes Ziel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Bestimmt Kalorienziel und Startseite.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(model.goals) { goal in
                            ChoiceChip(title: goal.title, isSelected: model.resolvedPrimaryGoal == goal) {
                                model.primaryGoal = goal
                            }
                        }
                    }
                }
                .padding(.top, Theme.Space.xs)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if model.goals.contains(.rehabilitation) {
                InfoNote(text: "Ein medizinisch begleitetes Rehabilitationsmodul wird erst nach fachlicher Prüfung angeboten. Bis dahin unterstützt dich Kern mit angepasstem Training nach deinen eigenen Vorgaben – ohne Diagnosen.",
                         symbol: "cross.case", tint: Theme.warning)
            }
        }
        .animation(.smooth, value: model.goals)
    }

    private func option(_ goal: FitnessGoal) -> some View {
        OnboardingOption(title: goal.title, subtitle: goal.subtitle, symbol: goal.symbol,
                         isSelected: model.goals.contains(goal),
                         badge: model.goals.count > 1 && model.resolvedPrimaryGoal == goal ? "Hauptziel" : nil) {
            model.toggle(goal)
        }
    }
}

// MARK: - Über dich

struct OnboardingAboutStep: View {
    @Bindable var model: OnboardingModel
    @State private var showsIdentity = false
    @State private var showsBodyFat = false

    var body: some View {
        OnboardingPage(title: "Über dich",
                       subtitle: "Diese Angaben brauchen wir für eine realistische Schätzung deines Energiebedarfs.") {
            TextField("Vorname (optional)", text: $model.name)
                .textContentType(.givenName)
                .font(.body)
                .padding(Theme.Space.s)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Geburtsdatum").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                HStack {
                    DatePicker("Geburtsdatum", selection: $model.birthDate,
                               in: ...Calendar.current.date(byAdding: .year, value: -13, to: .now)!,
                               displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Fmt.locale)
                    Spacer()
                    Text("\(model.age) Jahre").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(Theme.Space.s)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Für Berechnungen").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Picker("Physiologische Angabe", selection: $model.sex) {
                    ForEach(PhysiologicalSex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Wird nur für Energieformeln verwendet und getrennt von deinem Profil behandelt.")
                    .font(.footnote).foregroundStyle(.secondary)

                if showsIdentity {
                    TextField("Geschlechtsidentität (freiwillig)", text: $model.genderIdentity)
                        .padding(Theme.Space.s)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
                        .transition(.opacity)
                } else {
                    Button("Geschlechtsidentität im Profil angeben") { withAnimation(.smooth) { showsIdentity = true } }
                        .font(.footnote.weight(.medium))
                }
            }

            OnboardingNumberInput(title: "Körpergrösse", value: $model.heightCm, unit: "cm", step: 1, range: 100...250)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                OnboardingNumberInput(title: "Aktuelles Gewicht", value: $model.weightInput, unit: model.weightUnit.symbol,
                                      step: 0.5, range: model.weightUnit == .kg ? 25...350 : 55...770, fractionDigits: 1)
                Picker("Einheit", selection: Binding(get: { model.weightUnit }, set: { model.switchWeightUnit(to: $0) })) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }

            if showsBodyFat {
                OnboardingNumberInput(title: "Körperfettanteil",
                                      value: Binding(get: { model.bodyFatPercent ?? 20 }, set: { model.bodyFatPercent = $0 }),
                                      unit: "%", step: 0.5, range: 3...60, fractionDigits: 1)
                    .transition(.opacity)
                Button("Körperfett entfernen") {
                    withAnimation(.smooth) { model.bodyFatPercent = nil; showsBodyFat = false }
                }
                .font(.footnote.weight(.medium))
            } else {
                Button {
                    withAnimation(.smooth) { showsBodyFat = true; model.bodyFatPercent = model.bodyFatPercent ?? 20 }
                } label: {
                    Label("Körperfettanteil hinzufügen (optional)", systemImage: "plus")
                }
                .font(.subheadline.weight(.medium))
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Besondere Situation").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Picker("Besondere Situation", selection: $model.specialSituation) {
                    ForEach(SpecialSituation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, 6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
                if model.specialSituation != .none {
                    InfoNote(text: "Für \(model.specialSituation.title) gelten gesonderte Sicherheitsregeln. Kern plant dann kein Kaloriendefizit und empfiehlt fachliche Begleitung.",
                             symbol: "shield.lefthalf.filled", tint: Theme.warning)
                }
            }
        }
    }
}

// MARK: - Aktivität

struct OnboardingActivityStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage(title: "Wie aktiv bist du?",
                       subtitle: "Dein Alltag ohne gezieltes Training zählt am meisten. Kern lernt mit der Zeit dazu.") {
            VStack(spacing: Theme.Space.xs) {
                ForEach(ActivityLevel.allCases) { level in
                    OnboardingOption(title: level.title, subtitle: level.detail, isSelected: model.activity == level) {
                        model.activity = level
                    }
                }
            }

            Text("Trainingserfahrung")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Space.xs)
            VStack(spacing: Theme.Space.xs) {
                ForEach(TrainingExperience.allCases) { exp in
                    OnboardingOption(title: exp.title, subtitle: exp.detail, isSelected: model.experience == exp) {
                        model.experience = exp
                    }
                }
            }

            if model.experience != .none {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Trainingstage pro Woche").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                model.trainingDays = day
                            } label: {
                                Text("\(day)")
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(model.trainingDays == day ? Color.white : Color.primary)
                                    .background(model.trainingDays == day ? Theme.accent : Theme.surface,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(day) Tage")
                            .accessibilityAddTraits(model.trainingDays == day ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: model.trainingDays)
                }
                .padding(.top, Theme.Space.xs)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: model.experience)
    }
}

// MARK: - Ziel-Details

struct OnboardingGoalDetailsStep: View {
    @Bindable var model: OnboardingModel

    private var weightGoal: FitnessGoal? {
        model.goals.first(where: \.needsTargetWeight)
    }

    private var needsTraining: Bool { model.goals.contains(where: \.needsTrainingDetails) }
    private var needsAdapted: Bool { model.goals.contains(.adaptedTraining) || model.goals.contains(.rehabilitation) }

    var body: some View {
        OnboardingPage(title: "Dein Weg dorthin", subtitle: "Ein paar Details, damit dein Start wirklich zu dir passt.") {
            if let weightGoal {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    sectionTitle(weightGoal == .loseWeight ? "Abnehmen" : "Zunehmen", symbol: weightGoal.symbol)
                    OnboardingNumberInput(
                        title: "Wunschgewicht",
                        value: Binding(
                            get: { model.targetWeightInput ?? defaultTarget(for: weightGoal) },
                            set: { model.targetWeightInput = $0 }
                        ),
                        unit: model.weightUnit.symbol, step: 0.5,
                        range: model.weightUnit == .kg ? 30...300 : 66...660, fractionDigits: 1
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tempo").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Fmt.decimal(model.weeklyRateKg, maxDigits: 2)) kg pro Woche")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        Slider(value: $model.weeklyRateKg, in: model.rateRange, step: 0.05)
                        Text(model.rateDescription).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(Theme.Space.s)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))

                    if let weeks = estimatedWeeks {
                        InfoNote(text: "Bei diesem Tempo wären es rund \(weeks) Wochen. Das ist eine Orientierung, keine Vorhersage – Körpergewicht schwankt natürlich.",
                                 symbol: "calendar")
                    }
                }
            }

            if needsTraining {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    sectionTitle("Training", symbol: "dumbbell")
                    Text("Wo trainierst du?").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(TrainingLocation.allCases) { loc in
                            ChoiceChip(title: loc.title, symbol: loc.symbol, isSelected: model.location == loc) {
                                model.location = loc
                            }
                        }
                    }
                    Text("Dauer einer Einheit").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Picker("Dauer", selection: $model.sessionMinutes) {
                        ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Bevorzugte Methoden").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(OnboardingModel.methodOptions, id: \.self) { method in
                            ChoiceChip(title: method, isSelected: model.preferredMethods.contains(method)) {
                                if model.preferredMethods.contains(method) { model.preferredMethods.remove(method) }
                                else { model.preferredMethods.insert(method) }
                            }
                        }
                    }
                    textField("Stärken (optional)", text: $model.strengths)
                    textField("Schwächen oder Fokusbereiche (optional)", text: $model.weaknesses)
                }
            }

            if needsAdapted {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    sectionTitle("Angepasstes Training", symbol: "slider.horizontal.3")
                    textField("Gewünschte Anpassungen", text: $model.adaptationsNote, axis: .vertical)
                    textField("Bekannte Belastungsgrenzen", text: $model.loadLimitsNote, axis: .vertical)
                    textField("Nicht geeignete Übungen", text: $model.excludedExercises, axis: .vertical)
                    textField("Vorgaben von Fachpersonen (optional)", text: $model.professionalGuidelines, axis: .vertical)
                    InfoNote(text: "Kern stellt keine Diagnosen und ersetzt keine Behandlung. Deine Angaben werden als Regeln für die Übungsauswahl verwendet.",
                             symbol: "cross.case")
                }
            }
        }
    }

    private var estimatedWeeks: Int? {
        guard let target = model.targetWeightKg, model.weeklyRateKg > 0 else { return nil }
        let diff = abs(model.weightKg - target)
        guard diff > 0.5 else { return nil }
        return Int((diff / model.weeklyRateKg).rounded(.up))
    }

    private func defaultTarget(for goal: FitnessGoal) -> Double {
        let kg = goal == .loseWeight ? model.weightKg * 0.92 : model.weightKg * 1.05
        return (model.weightUnit.fromKg(kg) * 2).rounded() / 2
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.top, Theme.Space.xs)
    }

    private func textField(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField(title, text: text, axis: axis)
            .lineLimit(axis == .vertical ? 1...4 : 1...1)
            .padding(Theme.Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
    }
}

// MARK: - Ernährung

struct OnboardingNutritionStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage(title: "Deine Ernährung", subtitle: "Alles freiwillig – hilft bei Vorschlägen und Rezepten.") {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Ernährungsform").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(DietType.allCases) { diet in
                        ChoiceChip(title: diet.title, isSelected: model.diet == diet) { model.diet = diet }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Allergien & Unverträglichkeiten").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(OnboardingModel.allergyOptions, id: \.self) { item in
                        ChoiceChip(title: item, isSelected: model.allergies.contains(item)) {
                            if model.allergies.contains(item) { model.allergies.remove(item) } else { model.allergies.insert(item) }
                        }
                    }
                }
            }

            field("Was isst du nicht? (z. B. Pilze, Koriander)", text: $model.excludedFoods)
            field("Was isst du besonders gern?", text: $model.preferredFoods)

            HStack {
                Text("Mahlzeiten pro Tag")
                Spacer()
                Stepper("\(model.mealsPerDay)", value: $model.mealsPerDay, in: 1...8)
                    .fixedSize()
                    .monospacedDigit()
            }
            .padding(Theme.Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))

            VStack(spacing: 0) {
                Toggle("Kalorien- und Makroziel verwenden", isOn: $model.wantsCalorieTarget)
                    .padding(Theme.Space.s)
                Divider().padding(.leading, Theme.Space.s)
                Toggle("Interesse an Rezepten und Plänen", isOn: $model.wantsRecipes)
                    .padding(Theme.Space.s)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))

            if !model.wantsCalorieTarget {
                InfoNote(text: "Du kannst trotzdem alles erfassen. Kern zeigt dann Summen statt eines Budgets.")
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical)
            .lineLimit(1...3)
            .padding(Theme.Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
    }
}

// MARK: - Module

struct OnboardingModulesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage(title: "Deine Module",
                       subtitle: "Passend zu deinen Zielen vorausgewählt. Aktiviere nur, was du wirklich nutzt – alles ist später änderbar.") {
            VStack(spacing: Theme.Space.xs) {
                ForEach(AppModule.allCases) { module in
                    OnboardingOption(title: module.title, subtitle: module.detail, symbol: module.symbol,
                                     isSelected: model.modules.contains(module),
                                     badge: module.isSensitive ? "Sensibel" : nil) {
                        model.setModule(module, enabled: !model.modules.contains(module))
                    }
                }
            }
            if model.modules.contains(.cycle) {
                InfoNote(text: "Zyklusdaten werden besonders geschützt, bleiben lokal und werden nur mit deiner ausdrücklichen Zustimmung für Auswertungen genutzt.",
                         symbol: "lock")
            }
        }
    }
}

// MARK: - Zusammenfassung

struct OnboardingSummaryStep: View {
    @Bindable var model: OnboardingModel
    @State private var showsDetails = false
    @State private var appeared = false

    var body: some View {
        let result = model.energyResult
        OnboardingPage(title: "Dein Start", subtitle: "Eine erste Schätzung. Kern verfeinert sie anhand deiner Einträge – Änderungen schlägt Kern dir immer erst vor.") {
            if model.wantsCalorieTarget {
                Card {
                    CardHeader(title: "Tagesziel", symbol: "flame", tint: Theme.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.energy(Double(appeared ? result.calorieTarget : 0), unit: model.energyUnit))
                            .font(.metricLarge)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(model.energyUnit.symbol).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: Theme.Space.l) {
                        StatValue(value: "\(result.proteinG)", unit: "g", label: "Protein", tint: Theme.protein)
                        StatValue(value: "\(result.carbsG)", unit: "g", label: "Kohlenhydrate", tint: Theme.carbs)
                        StatValue(value: "\(result.fatG)", unit: "g", label: "Fett", tint: Theme.fat)
                    }
                }
            }

            Card {
                CardHeader(title: "Weitere Ziele", symbol: "target")
                RowLabel(title: "Wasser", symbol: "drop", tint: Theme.water, value: Fmt.volume(Double(result.waterMl)))
                if model.experience != .none {
                    RowLabel(title: "Training", symbol: "dumbbell", tint: Theme.training, value: "\(model.trainingDays)× pro Woche")
                }
                if let target = model.targetWeightKg {
                    RowLabel(title: "Wunschgewicht", symbol: "scalemass", tint: Theme.weight,
                             value: Fmt.weightWithUnit(target, unit: model.weightUnit))
                }
            }

            DisclosureGroup(isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(result.explanation.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            Text(line).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, Theme.Space.xs)
            } label: {
                Text("So wurde gerechnet").font(.subheadline.weight(.medium))
            }
            .padding(Theme.Space.m)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            ForEach(result.notes) { note in
                InfoNote(text: note.text,
                         symbol: note.severity == .warning ? "exclamationmark.triangle" : "info.circle",
                         tint: note.severity == .warning ? Theme.warning : .secondary)
            }

            InfoNote(text: "Kern ersetzt keine medizinische oder ernährungsfachliche Beratung.", symbol: "stethoscope")
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.9).delay(0.2)) { appeared = true }
        }
    }
}
