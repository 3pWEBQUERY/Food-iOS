import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Persönlicher KI-Coach: Chat mit Text, Sprache und Bildern, der kontrollierte
/// Aktionen in der App vorbereitet. Datenänderungen erfolgen nur nach Bestätigung
/// oder über ausdrücklich freigegebene Automatisierungsregeln.
struct CoachView: View {
    private let prefill: String?

    init(prefill: String?) {
        self.prefill = prefill
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var conversation = CoachConversation()
    @State private var speech = CoachSpeechRecognizer()
    @State private var draft = ""
    @State private var draftBeforeDictation = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var attachment: Data?
    @State private var pendingConfirmation: CoachPendingAction?
    @State private var editing: CoachPendingAction?
    @State private var showClearConfirm = false
    @FocusState private var inputFocused: Bool

    private var executor: ActionExecutor {
        ActionExecutor(context: context, router: router, prefs: prefs, dismiss: { dismiss() })
    }

    private var latestAssistantID: UUID? {
        messages.last(where: { !$0.isUser })?.id
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        CoachIntroHeader(isEmpty: messages.isEmpty, usesServer: usesServer) { suggestion in
                            send(suggestion)
                        }

                        ForEach(messages) { message in
                            CoachMessageRow(
                                message: message,
                                actions: CoachActionStore.actions(of: message),
                                showsQuickReplies: message.id == latestAssistantID && messages.last?.id == message.id,
                                onQuickReply: { send($0) },
                                onConfirm: { confirm($0, in: message) },
                                onReject: { reject($0, in: message) },
                                onEdit: { editing = CoachPendingAction(message: message, action: $0) },
                                onUndo: { undo($0, in: message) },
                                onChoice: { choose($1, for: $0, in: message) }
                            )
                            .id(message.id)
                        }

                        if conversation.isThinking {
                            CoachTypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, Theme.Space.s)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: conversation.isThinking) { _, thinking in
                    if thinking { withAnimation(.smooth) { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Schliessen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Änderungsprotokoll", systemImage: "clock.arrow.circlepath") { router.open(.auditLog) }
                        Button("Coach-Einstellungen", systemImage: "gearshape") { router.open(.settingsSection(.coach)) }
                        Divider()
                        Button("Verlauf löschen", systemImage: "trash", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Weitere Optionen")
                }
            }
            .confirmationDialog(
                pendingConfirmation?.action.title ?? "Bestätigen",
                isPresented: Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } }),
                titleVisibility: .visible,
                presenting: pendingConfirmation
            ) { pending in
                Button("Endgültig löschen", role: .destructive) { perform(pending.action, in: pending.message) }
                Button("Abbrechen", role: .cancel) {}
            } message: { pending in
                Text(pending.action.detail.isEmpty ? "Diese Aktion verändert deine Daten." : pending.action.detail)
            }
            .confirmationDialog("Chatverlauf löschen?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Verlauf löschen", role: .destructive) { conversation.clearHistory(in: context) }
            } message: {
                Text("Deine erfassten Einträge bleiben erhalten. Nur die Nachrichten werden entfernt.")
            }
            .sheet(item: $editing) { pending in
                CoachActionEditor(action: pending.action) { updated in
                    CoachActionStore.update(pending.message, actionID: updated.id, in: context) { action in
                        action = updated
                        CoachActionFormatter.refreshDetail(&action, context: context, prefs: prefs)
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                if let prefill, draft.isEmpty { draft = prefill }
            }
            .onChange(of: speech.transcript) { _, transcript in
                guard speech.isRecording || !transcript.isEmpty else { return }
                draft = [draftBeforeDictation, transcript].filter { !$0.isEmpty }.joined(separator: " ")
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        attachment = CoachImageCompressor.compress(data)
                    }
                    photoItem = nil
                }
            }
            .onDisappear { if speech.isRecording { speech.stop() } }
        }
    }

    private var usesServer: Bool {
        prefs.hasBackend && prefs.aiProcessingConsent && !prefs.isGuestMode
    }

    // MARK: Eingabe

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment, let image = UIImage(data: attachment) {
                HStack(spacing: 10) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Bild angehängt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        self.attachment = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Bild entfernen")
                }
                .padding(.horizontal, 4)
            }

            if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.body.weight(.medium))
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Bild anhängen")

                    HStack(alignment: .bottom, spacing: 8) {
                        TextField(speech.isRecording ? "Ich höre zu …" : "Nachricht an den Coach", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($inputFocused)
                            .padding(.vertical, 12)

                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: speech.isRecording ? "stop.fill" : "mic")
                                .font(.body.weight(.medium))
                                .foregroundStyle(speech.isRecording ? Theme.warning : .secondary)
                                .symbolEffect(.pulse, isActive: speech.isRecording)
                                .frame(width: 32, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(speech.isRecording ? "Aufnahme beenden" : "Spracheingabe")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 23, style: .continuous))

                    Button {
                        send(draft)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(canSend ? Glass.regular.tint(Theme.accent).interactive() : Glass.regular, in: .circle)
                    .disabled(!canSend || conversation.isThinking)
                    .accessibilityLabel("Senden")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.25), value: attachment != nil)
    }

    private func toggleDictation() {
        if speech.isRecording {
            speech.stop()
        } else {
            draftBeforeDictation = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await speech.start() }
        }
    }

    private func send(_ text: String) {
        if speech.isRecording { speech.stop() }
        let image = attachment
        let content = text
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil else { return }
        draft = ""
        draftBeforeDictation = ""
        attachment = nil
        let executor = self.executor
        Task {
            await conversation.send(text: content, image: image, context: context, prefs: prefs,
                                    profile: profiles.first, executor: executor)
        }
    }

    // MARK: Aktionen

    private func confirm(_ action: CoachAction, in message: CoachMessage) {
        if action.isDestructive {
            pendingConfirmation = CoachPendingAction(message: message, action: action)
        } else {
            perform(action, in: message)
        }
    }

    private func perform(_ action: CoachAction, in message: CoachMessage) {
        let updated = executor.apply(action)
        CoachActionStore.update(message, actionID: action.id, in: context) { $0 = updated }
    }

    private func reject(_ action: CoachAction, in message: CoachMessage) {
        CoachActionStore.update(message, actionID: action.id, in: context) { $0.status = .rejected }
    }

    private func undo(_ action: CoachAction, in message: CoachMessage) {
        let updated = executor.undo(action)
        CoachActionStore.update(message, actionID: action.id, in: context) { $0 = updated }
    }

    /// Übernimmt eine Auswahl. Eine gewählte Trainingseinheit gilt für alle Aktionen der Nachricht,
    /// die ebenfalls auf eine Einheit warten (z. B. Notiz und Belastung).
    private func choose(_ choice: CoachChoice, for action: CoachAction, in message: CoachMessage) {
        var all = CoachActionStore.actions(of: message)
        let needs = action.params[CoachParam.needs]
        for index in all.indices {
            let isTarget = all[index].id == action.id
            let sharesSession = needs == CoachParam.sessionID
                && all[index].status == .needsInput
                && all[index].params[CoachParam.needs] == CoachParam.sessionID
            guard isTarget || sharesSession else { continue }
            if choice.rejects {
                all[index].status = .rejected
                continue
            }
            for (key, value) in choice.params { all[index].params[key] = value }
            if let key = all[index].params[CoachParam.needs], all[index].params[key] != nil {
                all[index].params[CoachParam.needs] = nil
            }
            if all[index].params[CoachParam.needs] == nil {
                all[index].status = .proposed
            }
            all[index].choices = []
            CoachActionFormatter.refreshDetail(&all[index], context: context, prefs: prefs)
            if let error = ActionValidator.validate(all[index], prefs: prefs, context: context), all[index].status == .proposed {
                all[index].status = .failed
                all[index].resultNote = error
            }
        }
        CoachActionStore.setActions(all, on: message)
        context.saveQuietly()
    }
}

/// Aktion inkl. zugehöriger Nachricht (für Dialoge und Bearbeitung).
struct CoachPendingAction: Identifiable {
    let message: CoachMessage
    let action: CoachAction
    var id: UUID { action.id }
}

// MARK: - Kopfbereich

private struct CoachIntroHeader: View {
    let isEmpty: Bool
    let usesServer: Bool
    let onSuggestion: (String) -> Void

    static let suggestions = [
        "Heute 82,4 kg gewogen",
        "500 ml Wasser getrunken",
        "Wie war meine Woche?",
        "Was ist mein Grundumsatz?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wie kann ich helfen?")
                        .font(.title2.weight(.semibold))
                    Text("Erzähl mir in eigenen Worten, was du erfassen möchtest – ich bereite die Einträge vor, du bestätigst.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Theme.Space.s)

                FlowLayout(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button {
                            onSuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Theme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            InfoNote(
                text: usesServer
                    ? "Nachrichten und angehängte Bilder werden zur Verarbeitung an den Kern-Server übertragen. Deine Daten ändern sich erst nach deiner Bestätigung."
                    : "Deine Nachrichten werden ausschliesslich auf diesem Gerät verarbeitet. Erweiterte KI-Funktionen kannst du in den Coach-Einstellungen freigeben.",
                symbol: usesServer ? "server.rack" : "iphone"
            )
        }
    }
}

// MARK: - Nachricht

private struct CoachMessageRow: View {
    let message: CoachMessage
    let actions: [CoachAction]
    let showsQuickReplies: Bool
    let onQuickReply: (String) -> Void
    let onConfirm: (CoachAction) -> Void
    let onReject: (CoachAction) -> Void
    let onEdit: (CoachAction) -> Void
    let onUndo: (CoachAction) -> Void
    let onChoice: (CoachAction, CoachChoice) -> Void

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            if let data = message.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Angehängtes Bild")
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isUser ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Theme.accent : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxWidth: 320, alignment: message.isUser ? .trailing : .leading)
            }

            ForEach(actions) { action in
                CoachActionCard(
                    action: action,
                    onConfirm: { onConfirm(action) },
                    onReject: { onReject(action) },
                    onEdit: { onEdit(action) },
                    onUndo: { onUndo(action) },
                    onChoice: { onChoice(action, $0) }
                )
            }

            if showsQuickReplies && !message.quickReplies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(message.quickReplies, id: \.self) { reply in
                            Button {
                                onQuickReply(reply)
                            } label: {
                                Text(reply)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(Theme.accent)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

// MARK: - Aktionskarte

private struct CoachActionCard: View {
    let action: CoachAction
    let onConfirm: () -> Void
    let onReject: () -> Void
    let onEdit: () -> Void
    let onUndo: () -> Void
    let onChoice: (CoachChoice) -> Void

    private var tint: Color { action.isDestructive ? Theme.warning : Theme.accent }

    private var isEditable: Bool {
        [.logWeight, .logWater, .logFood, .addWorkoutNote, .setSessionExertion, .setWaterTarget].contains(action.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                    if !action.detail.isEmpty {
                        Text(action.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if action.isDerived && (action.status == .proposed || action.status == .needsInput) {
                Label("Aus deiner Beschreibung abgeleitet – bitte prüfen", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            if let note = action.resultNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(action.status == .failed ? Theme.warning : .secondary)
            }

            controls
        }
        .padding(14)
        .frame(maxWidth: 380, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var controls: some View {
        switch action.status {
        case .proposed:
            HStack(spacing: 8) {
                Button(primaryTitle, action: onConfirm)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                if isEditable {
                    Button("Bearbeiten", action: onEdit)
                        .buttonStyle(.glass)
                }
                if !action.isNavigation {
                    Button("Ablehnen", action: onReject)
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.small)
            .font(.subheadline.weight(.medium))

        case .needsInput:
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    ForEach(action.choices) { choice in
                        ChoiceChip(title: choice.label, isSelected: false) { onChoice(choice) }
                    }
                }
                HStack(spacing: 8) {
                    if isEditable {
                        Button("Eigener Wert", action: onEdit)
                            .buttonStyle(.glass)
                    }
                    Button("Ablehnen", action: onReject)
                        .buttonStyle(.glass)
                }
                .controlSize(.small)
                .font(.subheadline.weight(.medium))
            }

        case .applied:
            HStack {
                Label(action.wasAutoApplied ? "Automatisch angewendet" : (action.isNavigation ? "Geöffnet" : "Angewendet"),
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.positive)
                Spacer()
                if action.isUndoable {
                    Button("Rückgängig", action: onUndo)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .font(.subheadline.weight(.medium))
                }
            }

        case .rejected:
            Label("Abgelehnt", systemImage: "xmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

        case .undone:
            Label("Rückgängig gemacht", systemImage: "arrow.uturn.backward.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

        case .failed:
            HStack(spacing: 8) {
                Label("Nicht ausgeführt", systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                Spacer()
                if isEditable {
                    Button("Bearbeiten", action: onEdit)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private var primaryTitle: String {
        if action.isDestructive { return "Löschen …" }
        if action.isNavigation { return "Öffnen" }
        return "Bestätigen"
    }
}

// MARK: - Tipp-Indikator

private struct CoachTypingIndicator: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("Coach denkt nach")
    }
}

// MARK: - Bearbeiten

private struct CoachActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    let original: CoachAction
    let onSave: (CoachAction) -> Void

    @State private var number: Double?
    @State private var note: String
    @State private var day: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var meal: MealType
    @State private var exertion: Int

    init(action: CoachAction, onSave: @escaping (CoachAction) -> Void) {
        self.original = action
        self.onSave = onSave
        let p = action.params
        let initialNumber: Double?
        switch action.kind {
        case .logWeight: initialNumber = CoachParam.double(p[CoachParam.kg]).map { AppPreferences.shared.weightUnit.fromKg($0) }
        case .logWater, .setWaterTarget: initialNumber = CoachParam.double(p[CoachParam.ml])
        case .logFood: initialNumber = CoachParam.double(p[CoachParam.grams])
        default: initialNumber = nil
        }
        _number = State(initialValue: initialNumber)
        _note = State(initialValue: p[CoachParam.note] ?? "")
        let dayDate = p[CoachParam.day].flatMap { DayKey.date(from: $0) } ?? .now
        _day = State(initialValue: dayDate)
        _hasTime = State(initialValue: p[CoachParam.time] != nil)
        _time = State(initialValue: CoachParam.date(day: p[CoachParam.day], time: p[CoachParam.time]))
        _meal = State(initialValue: MealType(rawValue: p[CoachParam.meal] ?? "") ?? .suggested())
        _exertion = State(initialValue: Int(CoachParam.double(p[CoachParam.exertion]) ?? 7))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch original.kind {
                case .logWeight:
                    Section {
                        NumberField(title: "Gewicht", value: $number, unit: prefs.weightUnit.symbol, fractionDigits: 2)
                    }
                    dateSection
                case .logWater:
                    Section {
                        NumberField(title: "Menge", value: $number, unit: "ml", fractionDigits: 0)
                    }
                    dateSection
                case .setWaterTarget:
                    Section {
                        NumberField(title: "Trinkziel", value: $number, unit: "ml", fractionDigits: 0)
                    } footer: {
                        Text("Zwischen 500 und 6000 ml.")
                    }
                case .logFood:
                    Section {
                        NumberField(title: "Menge", value: $number, unit: "g", fractionDigits: 0)
                        Picker("Mahlzeit", selection: $meal) {
                            ForEach(MealType.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    dateSection
                case .addWorkoutNote:
                    Section("Notiz") {
                        TextField("Notiz", text: $note, axis: .vertical)
                            .lineLimit(3...8)
                    }
                case .setSessionExertion:
                    Section {
                        Stepper(value: $exertion, in: 1...10) {
                            HStack {
                                Text("Belastung")
                                Spacer()
                                Text("\(exertion)/10").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Session-RPE: 1 = sehr leicht, 10 = maximal anstrengend.")
                    }
                default:
                    Text("Diese Aktion kann nicht bearbeitet werden.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { save() }
                }
            }
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        Section {
            DatePicker("Tag", selection: $day, in: ...Date.now, displayedComponents: .date)
            Toggle("Uhrzeit angeben", isOn: $hasTime)
            if hasTime {
                DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text("Ohne Angabe speichert Kern keine erfundene Uhrzeit.")
        }
    }

    private func save() {
        var action = original
        switch action.kind {
        case .logWeight:
            if let number { action.params[CoachParam.kg] = CoachParam.string(prefs.weightUnit.toKg(number)) }
        case .logWater, .setWaterTarget:
            if let number { action.params[CoachParam.ml] = CoachParam.string(number) }
        case .logFood:
            if let number { action.params[CoachParam.grams] = CoachParam.string(number) }
            action.params[CoachParam.meal] = meal.rawValue
        case .addWorkoutNote:
            action.params[CoachParam.note] = note
        case .setSessionExertion:
            action.params[CoachParam.exertion] = String(exertion)
            action.isDerived = false
        default:
            break
        }
        if [.logWeight, .logWater, .logFood].contains(action.kind) {
            action.params[CoachParam.day] = DayKey.make(day)
            if hasTime {
                action.params[CoachParam.time] = Fmt.time(time)
            } else {
                action.params[CoachParam.time] = nil
            }
        }
        if let key = action.params[CoachParam.needs], action.params[key] != nil {
            action.params[CoachParam.needs] = nil
        }
        if action.params[CoachParam.needs] == nil, action.status == .needsInput || action.status == .failed {
            action.status = .proposed
            action.choices = []
            action.resultNote = nil
        }
        onSave(action)
        dismiss()
    }
}

// MARK: - Formatierung

@MainActor
enum CoachActionFormatter {
    /// Aktualisiert die Beschreibung anhand der aktuellen Parameter.
    static func refreshDetail(_ action: inout CoachAction, context: ModelContext, prefs: AppPreferences) {
        let p = action.params
        let when = CoachParam.dayDescription(p[CoachParam.day], time: p[CoachParam.time])
        switch action.kind {
        case .logWeight:
            if let kg = CoachParam.double(p[CoachParam.kg]) {
                action.detail = "\(Fmt.weightWithUnit(kg, unit: prefs.weightUnit, digits: 2)) · \(when)"
            }
        case .logWater:
            if let ml = CoachParam.double(p[CoachParam.ml]) {
                action.detail = "\(Fmt.volume(ml)) · \(when)"
            }
        case .setWaterTarget:
            if let ml = CoachParam.double(p[CoachParam.ml]) {
                action.detail = "Neues Tagesziel: \(Fmt.volume(ml))"
            }
        case .logFood:
            guard let grams = CoachParam.double(p[CoachParam.grams]) else { return }
            let meal = MealType(rawValue: p[CoachParam.meal] ?? "") ?? .suggested()
            var kcal: Double?
            var unit = "g"
            if let id = UUID(uuidString: p[CoachParam.foodID] ?? ""),
               let food = try? context.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })).first {
                kcal = food.per100.forGrams(grams).kcal
                unit = food.unitSymbol
            } else if let per100 = CoachParam.double(p[CoachParam.kcal100]) {
                kcal = per100 * grams / 100
            }
            var parts = ["\(Fmt.decimal(grams)) \(unit)", meal.title]
            if let kcal { parts.append(Fmt.energyWithUnit(kcal, unit: prefs.energyUnit)) }
            if action.isDerived || p[CoachParam.quality] == DataQuality.aiUnconfirmed.rawValue {
                parts.append("KI-Schätzung, unbestätigt")
            }
            action.detail = parts.joined(separator: " · ")
        case .addWorkoutNote, .setSessionExertion:
            var sessionName = "Einheit wählen"
            if let id = UUID(uuidString: p[CoachParam.sessionID] ?? ""),
               let session = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first {
                sessionName = "\(session.name.isEmpty ? "Training" : session.name) · \(Fmt.shortDate(session.startedAt))"
            }
            if action.kind == .addWorkoutNote {
                action.detail = "„\(p[CoachParam.note] ?? "")“ · \(sessionName)"
            } else {
                let value = p[CoachParam.exertion] ?? "–"
                action.detail = "\(value)/10 · \(sessionName)\(action.isDerived ? " · abgeleitet, bitte prüfen" : "")"
            }
        default:
            break
        }
    }
}

// MARK: - Bildkompression

enum CoachImageCompressor {
    /// Verkleinert Bilder auf max. 1600 px Kantenlänge (JPEG 80 %).
    static func compress(_ data: Data, maxDimension: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}
