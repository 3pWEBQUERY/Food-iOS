import SwiftUI
import SwiftData

/// Regelbasierte Planerstellung mit Vorschau, Begründung und bewusster Übernahme.
struct PlanGeneratorView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AppPreferences.self) private var prefs

    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query private var plans: [WorkoutPlan]

    @State private var days = 3
    @State private var minutes = 60
    @State private var focus: TrainingFocus = .hypertrophy
    @State private var location: TrainingLocation = .gym
    @State private var gymID: UUID?
    @State private var jointFriendly = false
    @State private var draft: TrainingPlanDraft?
    @State private var didLoad = false

    private var profile: UserProfile? { profiles.first }
    private var exerciseNames: [String: Exercise] {
        Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                optionsCard
                PrimaryActionButton(title: draft == nil ? "Plan erstellen" : "Neu berechnen", systemImage: "wand.and.stars") {
                    withAnimation(.smooth) { generate() }
                }
                if let draft {
                    preview(draft)
                }
                InfoNote(text: "Kern erstellt Pläne nach überprüfbaren Trainingsregeln. Bei Beschwerden, Verletzungen oder medizinischer Rehabilitation gelten die Vorgaben deiner Ärztin, deines Arztes oder deiner Physiotherapie. Kern stellt keine Diagnosen.",
                         symbol: "cross.case")
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .navigationTitle("Plan erstellen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDefaults)
    }

    // MARK: Optionen

    private var optionsCard: some View {
        Card {
            CardHeader(title: "Deine Vorgaben", symbol: "slider.horizontal.3", tint: Theme.training)

            Stepper(value: $days, in: 1...6) {
                LabeledContent("Trainingstage pro Woche", value: "\(days)")
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Dauer pro Einheit").font(.subheadline)
                Picker("Dauer", selection: $minutes) {
                    ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Schwerpunkt").font(.subheadline)
                FlowLayout(spacing: 8) {
                    ForEach(TrainingFocus.allCases) { item in
                        ChoiceChip(title: item.title, isSelected: focus == item) { focus = item }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Trainingsort").font(.subheadline)
                FlowLayout(spacing: 8) {
                    ForEach(TrainingLocation.allCases) { item in
                        ChoiceChip(title: item.title, symbol: item.symbol, isSelected: location == item) { location = item }
                    }
                }
                if (location == .gym || location == .mixed) && !gyms.isEmpty {
                    Picker("Studio", selection: $gymID) {
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(UUID?.some(gym.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.training)
                }
            }
            Divider()
            Toggle("Gelenkschonende Varianten bevorzugen", isOn: $jointFriendly)
                .font(.subheadline)
            if let profile, !(profile.loadLimitsNote.isEmpty && profile.adaptationsNote.isEmpty) {
                Text("Deine hinterlegten Hinweise: \([profile.loadLimitsNote, profile.adaptationsNote].filter { !$0.isEmpty }.joined(separator: " · "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Vorschau

    private func preview(_ draft: TrainingPlanDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(title: draft.name)

            Card {
                CardHeader(title: "Warum dieser Plan", symbol: "text.magnifyingglass", tint: Theme.training)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(draft.rationale, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.training).frame(width: 5, height: 5)
                            Text(line)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            ForEach(draft.days) { day in
                Card {
                    CardHeader(title: day.name, symbol: "calendar", tint: Theme.training) {
                        Text("ca. \(day.estimatedMinutes) min")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if day.exercises.isEmpty {
                        Text("Mit deiner Ausstattung konnten keine passenden Übungen gefunden werden.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(day.exercises) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(exerciseNames[item.exerciseID]?.name ?? item.exerciseID)
                                    .font(.subheadline.weight(.medium))
                                if item.warmupSets > 0 {
                                    Text("+ \(item.warmupSets) Aufwärmsätze")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(item.sets) × \(TrainingMath.repRange(min: item.repMin, max: item.repMax)) · RIR \(item.targetRIR ?? 2) · \(item.restSeconds) s")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !draft.weeklySets.isEmpty {
                Card {
                    CardHeader(title: "Arbeitssätze pro Woche", symbol: "chart.bar", tint: Theme.training)
                    let maxSets = max(draft.weeklySets.map(\.sets).max() ?? 1, 10)
                    ForEach(draft.weeklySets, id: \.muscle) { entry in
                        HStack(spacing: Theme.Space.s) {
                            Text(entry.muscle.title)
                                .font(.subheadline)
                                .frame(width: 100, alignment: .leading)
                            LinearMeter(progress: Double(entry.sets) / Double(maxSets), tint: Theme.training, showsOverflow: false)
                            Text("\(entry.sets)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    Text("Viele Empfehlungen nennen etwa 10–20 Arbeitssätze pro Muskelgruppe und Woche für den Muskelaufbau. Einsteiger profitieren bereits von weniger.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GlassEffectContainer(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Button {
                        withAnimation(.smooth) { self.draft = nil }
                    } label: {
                        Text("Verwerfen")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    PrimaryActionButton(title: "Annehmen", systemImage: "checkmark") { accept(draft) }
                }
            }
        }
    }

    // MARK: Logik

    private func loadDefaults() {
        guard !didLoad else { return }
        didLoad = true
        if let profile {
            days = profile.trainingDaysPerWeek.clamped(1...6)
            minutes = [30, 45, 60, 75, 90].min { abs($0 - profile.sessionDurationMin) < abs($1 - profile.sessionDurationMin) } ?? 60
            focus = PlanGenerator.defaultFocus(for: profile.primaryGoal)
            location = profile.trainingLocation
            jointFriendly = profile.goals.contains(.adaptedTraining) || profile.goals.contains(.rehabilitation)
                || !profile.loadLimitsNote.isEmpty || !profile.adaptationsNote.isEmpty
        }
        gymID = TrainingQueries.activeGym(in: context)?.id
    }

    private func generate() {
        let kinds: Set<EquipmentKind>
        var gymName: String?
        switch location {
        case .home:
            kinds = [.dumbbell, .band, .bodyweight, .kettlebell]
        case .outdoor:
            kinds = [.bodyweight, .band]
        case .gym, .mixed:
            if let gym = gyms.first(where: { $0.id == gymID }) {
                kinds = Set(gym.availableKinds).union([.bodyweight])
                gymName = gym.name
            } else {
                kinds = Set(EquipmentKind.allCases)
            }
        }
        let options = TrainingPlanOptions(
            daysPerWeek: days, sessionMinutes: minutes, focus: focus,
            experience: profile?.trainingExperience ?? .beginner,
            goal: profile?.primaryGoal ?? .buildMuscle,
            preferJointFriendly: jointFriendly,
            availableKinds: kinds,
            excludedExerciseIDs: Set(profile?.excludedExerciseIDs ?? []),
            gymName: gymName
        )
        draft = PlanGenerator.generate(options: options, exercises: exercises)
    }

    private func accept(_ draft: TrainingPlanDraft) {
        let plan = WorkoutPlan(name: draft.name, goal: draft.options.goal, daysPerWeek: draft.days.count, source: "generated")
        plan.rationale = draft.rationale.joined(separator: "\n")
        plan.gymID = gymID
        context.insert(plan)
        for (index, day) in draft.days.enumerated() {
            let template = WorkoutTemplate(name: day.name, order: index, exercises: day.exercises)
            plan.templates.append(template)
        }
        for other in plans where other.id != plan.id { other.isActive = false }
        plan.isActive = true
        AuditLog.record(context, actor: .user, summary: "Generierten Trainingsplan übernommen: \(plan.name)",
                        detail: draft.rationale.first ?? "", entityType: EntityType.plan, entityID: plan.id.uuidString)
        context.saveQuietly()
        router.trainingPath = [.plan(id: plan.id)]
    }
}
