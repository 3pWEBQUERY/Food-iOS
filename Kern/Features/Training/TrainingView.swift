import SwiftUI
import SwiftData

/// Tab „Training“: nächstes Training, Pläne, Vorschläge und Zugang zu Bibliothek und Verlauf.
struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(WorkoutStore.self) private var workouts
    @Environment(AppPreferences.self) private var prefs

    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted == true }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]

    @State private var suggestions: [TrainingSuggestion] = []
    @State private var showNewPlanAlert = false
    @State private var newPlanName = ""
    @State private var planToDelete: WorkoutPlan?

    private var activePlan: WorkoutPlan? { plans.first(where: \.isActive) }
    private var exerciseNames: [String: String] {
        Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                weekCard
                startSection
                if !suggestions.isEmpty { suggestionsSection }
                plansSection
                moreSection
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .navigationTitle("Training")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Eigenen Plan anlegen", systemImage: "square.and.pencil") {
                        newPlanName = ""
                        showNewPlanAlert = true
                    }
                    Button("Plan erstellen lassen", systemImage: "wand.and.stars") {
                        router.trainingPath.append(.planGenerator)
                    }
                } label: {
                    Label("Neuer Plan", systemImage: "plus")
                }
            }
        }
        .alert("Neuer Trainingsplan", isPresented: $showNewPlanAlert) {
            TextField("Name", text: $newPlanName)
            Button("Abbrechen", role: .cancel) {}
            Button("Anlegen") { createPlan() }
        } message: {
            Text("Du kannst Trainingstage und Übungen anschliessend hinzufügen.")
        }
        .confirmationDialog("Plan löschen?", isPresented: Binding(get: { planToDelete != nil }, set: { if !$0 { planToDelete = nil } }),
                            titleVisibility: .visible, presenting: planToDelete) { plan in
            Button("„\(plan.name)“ löschen", role: .destructive) { delete(plan) }
        } message: { _ in
            Text("Absolvierte Trainings bleiben in deinem Verlauf erhalten.")
        }
        .task(id: sessions.count) { refreshSuggestions() }
        .onAppear { workouts.validate(in: context) }
    }

    // MARK: Abschnitte

    private var weekCard: some View {
        Card {
            let weekStart = TrainingQueries.weekStart(for: .now)
            let thisWeek = sessions.filter { $0.startedAt >= weekStart }
            let target = (try? context.fetch(FetchDescriptor<UserProfile>()).first?.weeklyWorkoutTarget) ?? 3
            CardHeader(title: "Diese Woche", symbol: "calendar", tint: Theme.training) {
                Text("\(thisWeek.count) von \(target)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TrainingWeekStrip(sessions: thisWeek)
        }
    }

    @ViewBuilder
    private var startSection: some View {
        if workouts.hasActiveSession, let session = workouts.activeSession(in: context) {
            Card {
                CardHeader(title: "Training läuft", symbol: "timer", tint: Theme.training)
                Text(session.name)
                    .font(.title2.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text("Seit \(Fmt.duration(timeline.date.timeIntervalSince(session.startedAt))) · \(session.completedSetCount) Sätze erledigt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                PrimaryActionButton(title: "Fortsetzen", systemImage: "play.fill") {
                    router.isWorkoutPresented = true
                }
            }
        } else if let plan = activePlan, let template = TrainingQueries.nextTemplate(in: plan) {
            Card {
                CardHeader(title: "Nächstes Training", symbol: "dumbbell", tint: Theme.training) {
                    if let until = TrainingDeload.activeUntil(planID: plan.id) {
                        Badge(text: "Leichte Woche bis \(Fmt.shortDate(until))", tint: Theme.positive)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.title2.weight(.semibold))
                    Text(plan.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(template.exercises.prefix(6)) { item in
                        HStack {
                            Text(exerciseNames[item.exerciseID] ?? "Übung")
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.sets) × \(TrainingMath.repRange(min: item.repMin, max: item.repMax))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if template.exercises.count > 6 {
                        Text("+ \(template.exercises.count - 6) weitere")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    PrimaryActionButton(title: "Starten", systemImage: "play.fill") {
                        start(template: template, plan: plan)
                    }
                    Menu {
                        ForEach(plan.sortedTemplates) { other in
                            Button(other.name) { start(template: other, plan: plan) }
                        }
                        Divider()
                        Button("Freies Training", systemImage: "plus") { startEmpty() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityLabel("Anderen Trainingstag wählen")
                }
            }
        } else {
            Card {
                CardHeader(title: "Training starten", symbol: "dumbbell", tint: Theme.training)
                Text(plans.isEmpty ? "Noch kein Trainingsplan" : "Kein aktiver Plan")
                    .font(.title3.weight(.semibold))
                Text(plans.isEmpty
                     ? "Lass dir einen Plan aus deinen Zielen und deiner Ausstattung erstellen oder starte direkt ein freies Training."
                     : "Aktiviere einen Plan, damit Kern dein nächstes Training vorschlägt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: Theme.Space.s) {
                    if plans.isEmpty {
                        PrimaryActionButton(title: "Plan erstellen lassen", systemImage: "wand.and.stars") {
                            router.trainingPath.append(.planGenerator)
                        }
                    }
                    Button("Freies Training") { startEmpty() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Vorschläge")
            ForEach(suggestions) { suggestion in
                Card {
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        Image(systemName: suggestion.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.training)
                            .frame(width: 32, height: 32)
                            .background(Theme.training.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                            Text(suggestion.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: Theme.Space.xs) {
                        Button("Annehmen") {
                            ProgressionAdvisor.accept(suggestion, in: context)
                            withAnimation(.smooth) { refreshSuggestions() }
                        }
                        .buttonStyle(.glassProminent)
                        Button("Ablehnen") {
                            ProgressionAdvisor.dismiss(suggestion)
                            withAnimation(.smooth) { refreshSuggestions() }
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Pläne", actionTitle: "Neu") {
                newPlanName = ""
                showNewPlanAlert = true
            }
            if plans.isEmpty {
                Card {
                    Text("Pläne bestehen aus Trainingstagen mit Übungen, Sätzen und Wiederholungsbereichen. Du kannst sie jederzeit anpassen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                            NavigationLink(value: AppDestination.plan(id: plan.id)) {
                                HStack(spacing: Theme.Space.s) {
                                    RowLabel(title: plan.name,
                                             subtitle: "\(plan.templates.count) Trainingstage · \(plan.sourceRaw == "generated" ? "Erstellt von Kern" : "Eigener Plan")",
                                             symbol: plan.isActive ? "checkmark.circle.fill" : "list.bullet.rectangle",
                                             tint: plan.isActive ? Theme.training : .secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, Theme.Space.m)
                                .padding(.vertical, Theme.Space.s)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !plan.isActive {
                                    Button("Aktivieren", systemImage: "checkmark.circle") { activate(plan) }
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { planToDelete = plan }
                            }
                            if index < plans.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(title: "Mehr")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    moreRow("Übungsbibliothek", subtitle: "\(exercises.count) Übungen und Geräte", symbol: "books.vertical", destination: .exerciseLibrary)
                    Divider().padding(.leading, 60)
                    moreRow("Verlauf", subtitle: "\(sessions.count) absolvierte Trainings", symbol: "clock.arrow.circlepath", destination: .workoutHistory)
                    Divider().padding(.leading, 60)
                    moreRow("Gym-Profile", subtitle: "Verfügbare Geräte pro Studio", symbol: "building.2", destination: .gymProfiles)
                    Divider().padding(.leading, 60)
                    moreRow("Plan erstellen lassen", subtitle: "Regelbasiert aus Zielen und Ausstattung", symbol: "wand.and.stars", destination: .planGenerator)
                }
            }
        }
    }

    private func moreRow(_ title: String, subtitle: String, symbol: String, destination: AppDestination) -> some View {
        NavigationLink(value: destination) {
            HStack {
                RowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: Theme.training)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
        }
        .buttonStyle(.plain)
    }

    // MARK: Aktionen

    private func start(template: WorkoutTemplate, plan: WorkoutPlan) {
        workouts.start(template: template, plan: plan, name: template.name, in: context)
        router.isWorkoutPresented = true
    }

    private func startEmpty() {
        workouts.start(template: nil, plan: nil, name: "Freies Training", in: context)
        router.isWorkoutPresented = true
    }

    private func createPlan() {
        let name = newPlanName.trimmingCharacters(in: .whitespaces)
        let goal = (try? context.fetch(FetchDescriptor<UserProfile>()).first?.primaryGoal) ?? .buildMuscle
        let plan = WorkoutPlan(name: name.isEmpty ? "Mein Plan" : name, goal: goal, daysPerWeek: 3)
        context.insert(plan)
        let template = WorkoutTemplate(name: "Tag A", order: 0)
        plan.templates.append(template)
        if activePlan == nil { plan.isActive = true }
        AuditLog.record(context, actor: .user, summary: "Trainingsplan angelegt: \(plan.name)",
                        entityType: EntityType.plan, entityID: plan.id.uuidString)
        context.saveQuietly()
        router.trainingPath.append(.plan(id: plan.id))
    }

    private func activate(_ plan: WorkoutPlan) {
        for other in plans { other.isActive = other.id == plan.id }
        context.saveQuietly()
        refreshSuggestions()
    }

    private func delete(_ plan: WorkoutPlan) {
        AuditLog.record(context, actor: .user, summary: "Trainingsplan gelöscht: \(plan.name)",
                        entityType: EntityType.plan, entityID: plan.id.uuidString)
        context.delete(plan)
        context.saveQuietly()
        planToDelete = nil
    }

    private func refreshSuggestions() {
        guard let plan = activePlan else {
            suggestions = []
            return
        }
        suggestions = ProgressionAdvisor.suggestions(for: plan, in: context)
    }
}
