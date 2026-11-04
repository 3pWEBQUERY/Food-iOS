import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Entwurf

/// Bearbeitbarer Entwurf – das Modell wird erst beim Sichern verändert.
struct SupplementDraft: Identifiable, Hashable {
    var id = UUID()
    var existingID: UUID?
    var name = ""
    var brand = ""
    var barcode: String?
    var form: SupplementForm = .capsule
    var servingLabel = "1 Kapsel"
    var ingredients: [SupplementIngredient] = []
    var servingsPerIntake: Double = 1
    var frequency: SupplementFrequency = .daily
    var weekdays: Set<Int> = []
    var minutes: [Int] = [480]
    var remindersEnabled = false
    var stock: Double?
    var lowStockThreshold: Double = 7
    var infoURL = ""
    var notes = ""
    var quality: DataQuality = .community
    var source: FoodSource = .user

    init() {}

    init(_ s: Supplement) {
        existingID = s.id
        name = s.name
        brand = s.brand
        barcode = s.barcode
        form = s.form
        servingLabel = s.servingLabel
        ingredients = s.ingredients
        servingsPerIntake = s.servingsPerIntake
        frequency = s.frequency
        weekdays = Set(s.weekdays)
        minutes = s.scheduleMinutes
        remindersEnabled = s.remindersEnabled
        stock = s.stockServings
        lowStockThreshold = s.lowStockThreshold
        infoURL = s.infoURL ?? ""
        notes = s.notes
        quality = s.quality
        source = FoodSource(rawValue: s.sourceRaw) ?? .user
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && servingsPerIntake > 0
            && (frequency != .specificDays || !weekdays.isEmpty)
    }

    func apply(to s: Supplement) {
        s.name = name.trimmingCharacters(in: .whitespaces)
        s.brand = brand.trimmingCharacters(in: .whitespaces)
        s.barcode = barcode
        s.form = form
        s.servingLabel = servingLabel.isEmpty ? "1 Portion" : servingLabel
        s.ingredients = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount > 0 }
        s.servingsPerIntake = servingsPerIntake
        s.frequency = frequency
        s.weekdays = weekdays.sorted()
        s.scheduleMinutes = (minutes.isEmpty ? [480] : Array(Set(minutes))).sorted()
        s.remindersEnabled = remindersEnabled
        s.stockServings = stock
        s.lowStockThreshold = lowStockThreshold
        let url = infoURL.trimmingCharacters(in: .whitespaces)
        s.infoURL = url.isEmpty ? nil : url
        s.notes = notes
        s.qualityRaw = quality.rawValue
        s.sourceRaw = source.rawValue
    }
}

// MARK: - Editor

struct SupplementEditorView: View {
    @Environment(\.modelContext) private var context
    @State var draft: SupplementDraft
    var onFinish: () -> Void

    private static let weekdayOrder: [(Int, String)] = [(2, "Mo"), (3, "Di"), (4, "Mi"), (5, "Do"), (6, "Fr"), (7, "Sa"), (1, "So")]
    private static let units = ["mg", "µg", "g", "IE"]

    var body: some View {
        Form {
            Section("Produkt") {
                TextField("Name", text: $draft.name)
                TextField("Marke (optional)", text: $draft.brand)
                Picker("Form", selection: $draft.form) {
                    ForEach(SupplementForm.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                TextField("Portion laut Etikett, z. B. 2 Kapseln", text: $draft.servingLabel)
                if let barcode = draft.barcode {
                    LabeledContent("Barcode", value: barcode)
                }
                if draft.source != .user {
                    LabeledContent("Quelle") {
                        QualityBadge(quality: draft.quality)
                    }
                }
            }

            Section {
                ForEach($draft.ingredients) { $ingredient in
                    HStack {
                        TextField("Inhaltsstoff", text: $ingredient.name)
                        TextField("Menge", value: $ingredient.amount, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .monospacedDigit()
                        Picker("Einheit", selection: $ingredient.unit) {
                            ForEach(Self.units, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 72)
                    }
                }
                .onDelete { draft.ingredients.remove(atOffsets: $0) }
                Button {
                    draft.ingredients.append(SupplementIngredient(name: "", amount: 0, unit: "mg"))
                } label: {
                    Label("Inhaltsstoff hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Inhaltsstoffe pro Portion")
            } footer: {
                Text("Bitte mit dem Etikett abgleichen. Erkannte Werte können fehlerhaft sein.")
            }

            Section {
                Stepper(value: $draft.servingsPerIntake, in: 0.5...20, step: 0.5) {
                    LabeledContent("Deine dokumentierte Menge", value: "\(Fmt.decimal(draft.servingsPerIntake)) × \(draft.servingLabel)")
                }
                Picker("Häufigkeit", selection: $draft.frequency) {
                    ForEach(SupplementFrequency.allCases) { Text($0.title).tag($0) }
                }
                if draft.frequency == .specificDays {
                    HStack(spacing: 6) {
                        ForEach(Self.weekdayOrder, id: \.0) { day in
                            let selected = draft.weekdays.contains(day.0)
                            Button(day.1) {
                                if selected { draft.weekdays.remove(day.0) } else { draft.weekdays.insert(day.0) }
                            }
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Theme.supplement : Theme.fill, in: Circle())
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                if draft.frequency != .asNeeded {
                    ForEach(draft.minutes.indices, id: \.self) { index in
                        DatePicker("Zeitpunkt \(index + 1)", selection: minuteBinding(index), displayedComponents: .hourAndMinute)
                            .swipeActions {
                                if draft.minutes.count > 1 {
                                    Button(role: .destructive) { draft.minutes.remove(at: index) } label: { Label("Entfernen", systemImage: "trash") }
                                }
                            }
                    }
                    Button {
                        draft.minutes.append(min((draft.minutes.max() ?? 480) + 240, 1380))
                    } label: {
                        Label("Zeitpunkt hinzufügen", systemImage: "plus")
                    }
                    Toggle("Erinnerungen", isOn: $draft.remindersEnabled)
                }
            } header: {
                Text("Deine Routine")
            } footer: {
                Text("Kern gibt keine Dosierungsempfehlungen. Dokumentiert wird ausschliesslich die von dir festgelegte Menge.")
            }

            Section("Vorrat") {
                NumberField(title: "Verbleibende Portionen", value: $draft.stock, unit: "Port.", fractionDigits: 0)
                if draft.stock != nil {
                    Stepper(value: $draft.lowStockThreshold, in: 1...60, step: 1) {
                        LabeledContent("Hinweis ab", value: "\(Fmt.number(draft.lowStockThreshold)) Portionen")
                    }
                }
            }

            Section {
                TextField("Link zu geprüfter Fachinformation", text: $draft.infoURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Notizen", text: $draft.notes, axis: .vertical)
            } footer: {
                Text("Zum Beispiel eine Seite des BLV, der DGE oder deiner Ärztin bzw. deines Arztes.")
            }
        }
        .navigationTitle(draft.existingID == nil ? "Neues Supplement" : "Bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern", action: save).disabled(!draft.isValid)
            }
        }
    }

    private func minuteBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let minute = index < draft.minutes.count ? draft.minutes[index] : 480
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                guard index < draft.minutes.count else { return }
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.minutes[index] = (c.hour ?? 8) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func save() {
        let supplement: Supplement
        var isNew = false
        if let id = draft.existingID,
           let existing = try? context.fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.id == id })).first {
            supplement = existing
        } else {
            supplement = Supplement(name: draft.name)
            context.insert(supplement)
            isNew = true
        }
        draft.apply(to: supplement)
        supplement.isActive = true
        AuditLog.record(context, actor: .user,
                        summary: isNew ? "Supplement \(supplement.name) hinzugefügt" : "Supplement \(supplement.name) bearbeitet",
                        entityType: "Supplement", entityID: supplement.id.uuidString)
        context.saveQuietly()
        SupplementPlanner.updateReminders(for: supplement)
        onFinish()
    }
}

// MARK: - Hinzufügen

/// Hinzufügen über Suche in der eigenen Datenbank, Barcode, Etikett-Foto oder manuell.
struct SupplementAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Supplement.name) private var supplements: [Supplement]

    @State private var query = ""
    @State private var route: SupplementDraft?
    @State private var isScanning = false
    @State private var isShowingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var status: String?
    @State private var isWorking = false

    private var matches: [Supplement] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return supplements.filter { !$0.isActive } }
        return supplements.filter { "\($0.name) \($0.brand)".lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    actionRow("Barcode scannen", "barcode.viewfinder") { isScanning = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        actionRow("Etikett fotografieren", "camera.viewfinder") { isShowingCamera = true }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        RowLabel(title: "Etikett aus Fotos", symbol: "photo", tint: Theme.supplement)
                    }
                    .buttonStyle(.plain)
                    actionRow("Manuell eingeben", "square.and.pencil") { route = SupplementDraft() }
                }

                if isWorking || status != nil {
                    Section {
                        HStack(spacing: Theme.Space.s) {
                            if isWorking { ProgressView() }
                            Text(status ?? "").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if !matches.isEmpty {
                    Section(query.isEmpty ? "Pausierte Supplements" : "In deiner Datenbank") {
                        ForEach(matches) { s in
                            Button {
                                route = SupplementDraft(s)
                            } label: {
                                HStack {
                                    RowLabel(title: s.name, subtitle: s.brand.isEmpty ? s.form.title : s.brand,
                                             symbol: s.form.symbol, tint: Theme.supplement)
                                    if !s.isActive { Badge(text: "Pausiert") }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "In deinen Supplements suchen")
            .navigationTitle("Supplement hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $route) { draft in
                SupplementEditorView(draft: draft) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
            .sheet(isPresented: $isScanning) {
                SupplementScannerSheet { code in handleBarcode(code) }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                SupplementCameraPicker(isPresented: $isShowingCamera) { image in readLabel(image) }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        readLabel(image)
                    }
                    photoItem = nil
                }
            }
        }
    }

    private func actionRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RowLabel(title: title, symbol: symbol, tint: Theme.supplement)
        }
        .buttonStyle(.plain)
    }

    /// Reihenfolge: eigene Datenbank → Open Food Facts → manueller Entwurf.
    private func handleBarcode(_ code: String) {
        if let existing = supplements.first(where: { $0.barcode == code }) {
            route = SupplementDraft(existing)
            return
        }
        isWorking = true
        status = "Suche Produkt …"
        Task {
            let result = await SupplementLookup.openFoodFacts(barcode: code)
            var draft = SupplementDraft()
            draft.barcode = code
            if let result {
                draft.name = result.name
                draft.brand = result.brand
                draft.source = .openFoodFacts
                draft.quality = .community
                status = "Gefunden bei Open Food Facts (ODbL). Bitte Angaben prüfen."
            } else {
                status = "Kein Eintrag gefunden – bitte manuell ergänzen."
            }
            isWorking = false
            route = draft
        }
    }

    private func readLabel(_ image: UIImage) {
        isWorking = true
        status = "Etikett wird gelesen …"
        Task {
            let parsed = await SupplementLabelReader.read(image)
            var draft = SupplementDraft()
            draft.name = parsed.nameCandidate ?? ""
            draft.ingredients = parsed.ingredients
            draft.source = .ai
            draft.quality = .aiUnconfirmed
            isWorking = false
            status = parsed.ingredients.isEmpty
                ? "Keine Inhaltsstoffe erkannt. Bitte manuell ergänzen."
                : "\(parsed.ingredients.count) Inhaltsstoff(e) erkannt – bitte mit dem Etikett abgleichen."
            route = draft
        }
    }
}

// MARK: - Detail

struct SupplementDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var supplement: Supplement
    @Query(sort: \SupplementIntake.date, order: .reverse) private var allIntakes: [SupplementIntake]

    @State private var editing: SupplementDraft?
    @State private var isConfirmingDelete = false
    @State private var refill: Double?

    private var intakes: [SupplementIntake] { allIntakes.filter { $0.supplementID == supplement.id } }

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: supplement.form.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.supplement)
                        .frame(width: 52, height: 52)
                        .background(Theme.supplement.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(supplement.name).font(.headline)
                        Text([supplement.brand, supplement.form.title].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !supplement.isActive { Badge(text: "Pausiert", tint: Theme.warning) }
                    }
                }
                LabeledContent("Deine dokumentierte Menge", value: "\(Fmt.decimal(supplement.servingsPerIntake)) × \(supplement.servingLabel)")
                LabeledContent("Routine", value: routineText)
                if let adherence = SupplementPlanner.adherence(of: supplement, intakes: intakes, days: 30) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Eingehalten (30 Tage)", value: Fmt.percent(adherence))
                        LinearMeter(progress: adherence, tint: Theme.supplement)
                    }
                }
            }

            if !supplement.ingredients.isEmpty {
                Section("Inhaltsstoffe pro Portion") {
                    ForEach(supplement.ingredients) { ingredient in
                        LabeledContent(ingredient.name, value: "\(SupplementPlanner.formatAmount(ingredient.amount)) \(ingredient.unit)")
                    }
                }
            }

            Section("Vorrat") {
                if let stock = supplement.stockServings {
                    LabeledContent("Verbleibend", value: "\(Fmt.number(stock)) Portionen")
                    if supplement.servingsPerIntake > 0, supplement.frequency != .asNeeded {
                        let perDay = supplement.servingsPerIntake * Double(max(supplement.scheduleMinutes.count, 1))
                        LabeledContent("Reicht etwa", value: "\(Int(stock / perDay)) Tage")
                    }
                    if supplement.isLowOnStock {
                        Label("Vorrat geht zur Neige", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                    }
                } else {
                    Text("Kein Vorrat erfasst.").foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Portionen auffüllen", value: $refill, format: .number)
                        .keyboardType(.numberPad)
                    Button("Hinzufügen") {
                        guard let refill, refill > 0 else { return }
                        supplement.stockServings = (supplement.stockServings ?? 0) + refill
                        self.refill = nil
                        context.saveQuietly()
                    }
                    .disabled((refill ?? 0) <= 0)
                }
            }

            Section("Verlauf") {
                if intakes.isEmpty {
                    Text("Noch keine Einnahmen dokumentiert.").foregroundStyle(.secondary)
                }
                ForEach(intakes.prefix(30)) { intake in
                    HStack {
                        Text(Fmt.day(intake.date))
                        Spacer()
                        Text("\(Fmt.time(intake.date)) · \(Fmt.decimal(intake.servings))×")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { SupplementPlanner.undo(intake, in: context) } label: {
                            Label("Entfernen", systemImage: "trash")
                        }
                    }
                }
            }

            if let info = supplement.infoURL, let url = URL(string: info) {
                Section {
                    Link(destination: url) {
                        Label("Fachinformation öffnen", systemImage: "book")
                    }
                }
            }

            Section {
                Button(supplement.isActive ? "Pausieren" : "Fortsetzen") {
                    supplement.isActive.toggle()
                    context.saveQuietly()
                    SupplementPlanner.updateReminders(for: supplement)
                }
                Button("Supplement löschen", role: .destructive) { isConfirmingDelete = true }
            } footer: {
                Text("Beim Löschen bleibt dein Einnahmeverlauf erhalten.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(supplement.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") { editing = SupplementDraft(supplement) }
            }
        }
        .sheet(item: $editing) { draft in
            NavigationStack {
                SupplementEditorView(draft: draft) { editing = nil }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen", role: .cancel) { editing = nil }
                        }
                    }
            }
        }
        .confirmationDialog("\(supplement.name) löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                let target = supplement
                SupplementPlanner.removeReminders(for: target)
                AuditLog.record(context, actor: .user, summary: "Supplement \(target.name) gelöscht",
                                entityType: "Supplement", entityID: target.id.uuidString)
                dismiss()
                // Erst nach dem Schliessen löschen, damit die Ansicht kein gelöschtes Objekt rendert.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    context.delete(target)
                    context.saveQuietly()
                }
            }
        }
    }

    private var routineText: String {
        switch supplement.frequency {
        case .asNeeded:
            return "Nach Bedarf"
        case .daily:
            return "Täglich · " + supplement.scheduleMinutes.sorted().map(Fmt.minuteOfDay).joined(separator: ", ")
        case .specificDays:
            let names = [2: "Mo", 3: "Di", 4: "Mi", 5: "Do", 6: "Fr", 7: "Sa", 1: "So"]
            let order = [2, 3, 4, 5, 6, 7, 1]
            let days = order.filter { supplement.weekdays.contains($0) }.compactMap { names[$0] }.joined(separator: " ")
            return "\(days) · " + supplement.scheduleMinutes.sorted().map(Fmt.minuteOfDay).joined(separator: ", ")
        }
    }
}
