import SwiftData
import SwiftUI

// MARK: - Module

struct SettingsModulesForm: View {
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                ForEach(AppModule.allCases) { module in
                    Toggle(isOn: Binding(get: { prefs.isEnabled(module) },
                                         set: { prefs.setModule(module, enabled: $0) })) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(module.title)
                                Text(module.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(symbol: module.symbol, tint: module.tint)
                        }
                    }
                }
            } footer: {
                Text("Module sind unabhängig von deinen Zielen. Beim Deaktivieren bleiben alle Daten erhalten – sie werden nur ausgeblendet.")
            }

            if prefs.isEnabled(.cycle) {
                Section {
                    Toggle("Zyklusdaten für Auswertungen nutzen", isOn: $prefs.cycleAnalysisConsent)
                } header: {
                    Text("Zyklus – ausdrückliche Zustimmung")
                } footer: {
                    Text("Nur mit deiner Zustimmung stellt Kern zeitliche Zusammenhänge zwischen Zyklus, Training und Gewicht dar. Zyklusdaten werden nie an den KI-Server übertragen und nie für Werbung genutzt.")
                }
            }

            if prefs.isEnabled(.cycle) || prefs.isEnabled(.progressPhotos) {
                Section {
                    Toggle("Mit Face ID schützen", isOn: $prefs.lockSensitiveModules)
                } header: {
                    Text("Sensible Bereiche")
                } footer: {
                    Text("Zyklus und Fortschrittsfotos werden erst nach Entsperrung mit Face ID bzw. Code angezeigt.")
                }
            }
        }
    }
}

// MARK: - Startseite

struct SettingsDashboardForm: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router
    let profile: UserProfile?

    var body: some View {
        Form {
            Section {
                Button {
                    router.present(.dashboardEditor)
                } label: {
                    Label("Karten anordnen und auswählen", systemImage: "rectangle.3.group")
                }
                if let profile {
                    Button {
                        prefs.dashboardCards = DashboardCardKind.defaults(for: profile.primaryGoal)
                    } label: {
                        Label("Standard für „\(profile.primaryGoal.title)“ wiederherstellen", systemImage: "arrow.counterclockwise")
                    }
                }
            } footer: {
                Text("Die Navigation bleibt immer gleich – nur die Startseite passt sich deinen Zielen an.")
            }

            Section("Aktuelle Reihenfolge") {
                ForEach(Array(prefs.visibleDashboardCards.enumerated()), id: \.element) { index, card in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Image(systemName: card.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        Text(card.title)
                    }
                }
            }
        }
    }
}

// MARK: - Einheiten

struct SettingsUnitsForm: View {
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Picker("Gewicht", selection: $prefs.weightUnit) {
                    ForEach(WeightUnit.allCases) { Text($0.title).tag($0) }
                }
                Picker("Energie", selection: $prefs.energyUnit) {
                    ForEach(EnergyUnit.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Kern speichert intern immer metrisch. Die Umrechnung betrifft nur die Anzeige und Eingabe.")
            }
        }
    }
}

// MARK: - Apple Health

struct SettingsHealthForm: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @State private var isWorking = false
    @State private var importMessage: String?

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            if !health.isAvailable {
                Section {
                    InfoNote(text: "Apple Health ist auf diesem Gerät nicht verfügbar.", symbol: "heart.slash")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Toggle("Mit Apple Health verbinden", isOn: Binding(
                    get: { prefs.healthKitEnabled },
                    set: { enable in
                        if enable { connect() } else { prefs.healthKitEnabled = false }
                    }
                ))
                .disabled(!health.isAvailable || isWorking)
            } footer: {
                Text("Gelesen: Gewicht, Körperfett, Schritte, Aktivitätsenergie, Trainings und – falls erforderlich – Herzfrequenz. Geschrieben: Gewicht, Nährwerte, Wasser und Krafttrainings. Berechtigungen kannst du jederzeit in der Health-App unter Teilen → Apps → Kern ändern.")
            }

            if prefs.healthKitEnabled {
                Section("Heute") {
                    LabeledContent("Schritte", value: health.todaySteps.map { Fmt.number($0) } ?? "–")
                    LabeledContent("Aktivitätsenergie", value: health.todayActiveEnergyKcal.map { Fmt.energyWithUnit($0, unit: prefs.energyUnit) } ?? "–")
                    if let last = health.lastSyncAt {
                        LabeledContent("Zuletzt abgeglichen", value: "\(Fmt.day(last)), \(Fmt.time(last))")
                    }
                    Button {
                        importNow()
                    } label: {
                        HStack {
                            Text("Gewichte jetzt importieren")
                            Spacer()
                            if isWorking { ProgressView() }
                        }
                    }
                    .disabled(isWorking)
                    if let importMessage {
                        Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Aktivitätskalorien zum Budget addieren", isOn: $prefs.addActiveEnergyToBudget)
                } header: {
                    Text("Kalorienbudget")
                } footer: {
                    Text("Standardmässig aus: Dein Aktivitätsniveau ist im Gesamtbedarf bereits enthalten. Wenn du Aktivitätskalorien zusätzlich addierst, wählst du am besten „Überwiegend sitzend“ als Aktivitätsniveau – sonst wird Bewegung doppelt gezählt.")
                }

                Section {
                    InfoNote(text: "Duplikate werden verhindert: Eigene Einträge erhalten eine eindeutige Kennung, importierte Messungen werden über ihre Health-ID und Zeitpunkt abgeglichen.",
                             symbol: "checkmark.shield")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if let error = health.lastError {
                Section {
                    Text(error).font(.footnote).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private func connect() {
        isWorking = true
        Task {
            let ok = await health.requestAuthorization()
            prefs.healthKitEnabled = ok
            if ok {
                await health.refreshToday()
                let count = await health.importWeights(into: context)
                importMessage = count > 0 ? "\(count) Messung(en) übernommen." : nil
            }
            isWorking = false
        }
    }

    private func importNow() {
        isWorking = true
        Task {
            let count = await health.importWeights(into: context)
            await health.refreshToday()
            importMessage = count > 0 ? "\(count) neue Messung(en) übernommen." : "Keine neuen Messungen gefunden."
            isWorking = false
        }
    }
}

// MARK: - Erinnerungen

struct SettingsNotificationsForm: View {
    @Environment(AppPreferences.self) private var prefs
    @AppStorage("kern.reminder.weigh.minute") private var weighMinute = 7 * 60
    @AppStorage("kern.reminder.meal.minute") private var mealMinute = 20 * 60
    @State private var deniedNote = false

    private static let waterHours = [10, 12, 14, 16, 18]

    var body: some View {
        Form {
            Section {
                Toggle("Trinkerinnerungen", isOn: binding(\.waterReminderEnabled, apply: scheduleWater, cancelPrefix: "kern.reminder.water"))
            } footer: {
                Text("Zwischen 10 und 18 Uhr alle zwei Stunden.")
            }

            Section {
                Toggle("Wiegen", isOn: binding(\.weighInReminderEnabled, apply: scheduleWeigh, cancelPrefix: "kern.reminder.weigh"))
                if prefs.weighInReminderEnabled {
                    DatePicker("Uhrzeit", selection: minuteBinding($weighMinute, onChange: scheduleWeigh), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Am aussagekräftigsten ist das Wiegen morgens, unter gleichen Bedingungen. Einzelne Messungen verändern deine Ziele nicht.")
            }

            Section {
                Toggle("Tagebuch vervollständigen", isOn: binding(\.mealReminderEnabled, apply: scheduleMeal, cancelPrefix: "kern.reminder.meal"))
                if prefs.mealReminderEnabled {
                    DatePicker("Uhrzeit", selection: minuteBinding($mealMinute, onChange: scheduleMeal), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Erinnerungen für Supplements und den Zyklus legst du direkt im jeweiligen Bereich fest.")
            }

            if deniedNote {
                Section {
                    InfoNote(text: "Mitteilungen sind für Kern deaktiviert. Du kannst sie in den iOS-Einstellungen unter Mitteilungen erlauben.",
                             symbol: "bell.slash", tint: Theme.warning)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<AppPreferences, Bool>, apply: @escaping () -> Void,
                         cancelPrefix: String) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { enabled in
                if enabled {
                    Task {
                        let granted = await NotificationManager.requestAuthorization()
                        prefs[keyPath: keyPath] = granted
                        deniedNote = !granted
                        if granted { apply() }
                    }
                } else {
                    prefs[keyPath: keyPath] = false
                    NotificationManager.cancel(prefix: cancelPrefix)
                }
            }
        )
    }

    private func minuteBinding(_ minute: Binding<Int>, onChange: @escaping () -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                onChange()
            }
        )
    }

    private func scheduleWater() {
        NotificationManager.cancel(prefix: "kern.reminder.water")
        for hour in Self.waterHours {
            NotificationManager.schedule(id: "kern.reminder.water.\(hour)", title: "Zeit für ein Glas Wasser",
                                         body: "Kurz erfassen hilft dir, dein Trinkziel zu erreichen.", hour: hour, minute: 0)
        }
    }

    private func scheduleWeigh() {
        NotificationManager.cancel(prefix: "kern.reminder.weigh")
        NotificationManager.schedule(id: "kern.reminder.weigh", title: "Wiegen",
                                     body: "Am besten morgens, vor dem Frühstück.", hour: weighMinute / 60, minute: weighMinute % 60)
    }

    private func scheduleMeal() {
        NotificationManager.cancel(prefix: "kern.reminder.meal")
        NotificationManager.schedule(id: "kern.reminder.meal", title: "Tagebuch vervollständigen",
                                     body: "Fehlt noch eine Mahlzeit von heute?", hour: mealMinute / 60, minute: mealMinute % 60)
    }
}

// MARK: - KI-Coach

struct SettingsCoachForm: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.modelContext) private var context
    @State private var showClearConfirm = false
    @State private var backendDraft = ""

    static let automations: [(key: String, title: String, detail: String)] = [
        ("water.autoApply", "Wasser direkt übernehmen", "z. B. „500 ml getrunken“"),
        ("weight.autoApply", "Gewicht direkt übernehmen", "z. B. „Heute 82,4 kg“"),
        ("supplement.autoApply", "Supplement-Einnahmen direkt übernehmen", "z. B. „Kreatin genommen“")
    ]

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle("Serverseitige KI erlauben", isOn: $prefs.aiProcessingConsent)
                    .disabled(prefs.isGuestMode)
            } header: {
                Text("Zustimmung")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ohne Zustimmung arbeitet der Coach vollständig auf deinem Gerät.")
                    Text("Mit Zustimmung werden an den Kern-Server übertragen: deine Nachricht, angehängte Bilder sowie Hauptziel und Masseinheiten. Nicht übertragen werden Zyklusdaten, Fortschrittsfotos, Apple-Health-Rohdaten und dein vollständiger Verlauf.")
                    Text("Die Zustimmung kannst du jederzeit widerrufen. Daten werden nicht für Werbung verwendet.")
                    if prefs.isGuestMode {
                        Text("Im Testmodus ist die serverseitige KI nicht verfügbar.")
                    }
                }
            }

            Section {
                ForEach(Self.automations, id: \.key) { rule in
                    Toggle(isOn: Binding(
                        get: { prefs.coachAutomations.contains(rule.key) },
                        set: { on in
                            if on { prefs.coachAutomations.insert(rule.key) } else { prefs.coachAutomations.remove(rule.key) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.title)
                            Text(rule.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Automatisierungen")
            } footer: {
                Text("Freigegebene Aktionen übernimmt der Coach ohne Vorschau – du siehst sie trotzdem im Chat und kannst sie rückgängig machen. Löschungen erfordern immer eine ausdrückliche Bestätigung. Alle Änderungen erscheinen im Änderungsprotokoll.")
            }

            Section {
                NavigationLink(value: AppDestination.auditLog) {
                    Label("Änderungsprotokoll", systemImage: "clock.arrow.circlepath")
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Chatverlauf löschen", systemImage: "trash")
                }
            }

            Section {
                TextField("https://api.example.ch", text: $backendDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { prefs.backendBaseURL = backendDraft.trimmingCharacters(in: .whitespaces) }
                LabeledContent("Status", value: prefs.hasBackend ? "Konfiguriert" : "Nur lokal")
            } header: {
                Text("Entwickler")
            } footer: {
                Text("Basis-URL des Kern-Backends. Leer lassen für rein lokalen Betrieb.")
            }
        }
        .onAppear { backendDraft = prefs.backendBaseURL }
        .onDisappear { prefs.backendBaseURL = backendDraft.trimmingCharacters(in: .whitespaces) }
        .confirmationDialog("Chatverlauf löschen?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Verlauf löschen", role: .destructive) {
                let all = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
                for message in all { context.delete(message) }
                context.saveQuietly()
            }
        } message: {
            Text("Deine erfassten Einträge bleiben erhalten.")
        }
    }
}

// MARK: - Einführung & Hilfe

struct SettingsTutorialForm: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    static let faqs: [(question: String, answer: String)] = [
        ("Wie berechnet Kern mein Kalorienziel?",
         "Kern schätzt deinen Grundumsatz mit etablierten Formeln (Mifflin-St.-Jeor oder Müller), multipliziert ihn mit deinem Aktivitätsfaktor und passt ihn an dein Ziel an. Sicherheitsregeln verhindern zu niedrige Zielwerte."),
        ("Warum schlägt Kern neue Zielwerte vor?",
         "Mit ausreichend erfassten Tagen und Wägungen vergleicht Kern deine durchschnittliche Aufnahme mit deinem Gewichtstrend. Daraus entsteht eine genauere Schätzung – du entscheidest, ob du sie übernimmst."),
        ("Was bedeuten die Qualitätsstufen bei Lebensmitteln?",
         "Verifiziert, Herstellerangaben, Referenzwert, Community-Eintrag, KI-erkannt oder unvollständig. So siehst du immer, wie verlässlich ein Nährwert ist. Bestehende Tagebucheinträge ändern sich nicht, wenn ein Produkt später korrigiert wird."),
        ("Was darf der Coach?",
         "Der Coach bereitet Einträge vor, öffnet Bereiche und erklärt Auswertungen. Datenänderungen erfolgen erst nach deiner Bestätigung oder über Automatisierungen, die du selbst freigibst. Diagnosen stellt er nicht."),
        ("Werden meine Daten geteilt?",
         "Nein. Deine Daten liegen verschlüsselt auf deinem Gerät. Externe Dienste nutzt Kern nur, wenn du sie aktivierst – z. B. Apple Health oder die serverseitige KI.")
    ]

    var body: some View {
        Form {
            Section {
                Button {
                    prefs.hasSeenTutorial = false
                    router.todayPath = []
                    router.show(tab: .today)
                } label: {
                    Label("Einführung erneut starten", systemImage: "play.circle")
                }
            } footer: {
                Text("Die kurze Einführung zeigt dir die wichtigsten Bereiche. Du kannst sie jederzeit überspringen.")
            }

            Section("Häufige Fragen") {
                ForEach(Self.faqs, id: \.question) { faq in
                    DisclosureGroup(faq.question) {
                        Text(faq.answer)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// MARK: - Über Kern

struct SettingsAboutForm: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kern")
                        .font(.title2.weight(.semibold))
                    Text("Tracke nicht nur, was du isst und trainierst. Verstehe, wie du dich entwickelst.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                LabeledContent("Version", value: version)
            }

            Section("Datenquellen") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kern Basisdaten")
                    Text("Generische Referenzwerte für Grundnahrungsmittel. Werte können je nach Produkt abweichen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open Food Facts")
                    Text("Produktdaten aus der offenen Datenbank, lizenziert unter der Open Database License (ODbL). Einträge werden getrennt und mit Quelle gekennzeichnet.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let url = URL(string: "https://world.openfoodfacts.org") {
                        Link("openfoodfacts.org", destination: url).font(.footnote)
                    }
                }
            }

            Section("Methoden") {
                Text("Grundumsatz: Mifflin-St.-Jeor (1990), Müller et al. (2004), Katch-McArdle. Geschätztes Einerwiederholungsmaximum: Epley. Adaptive Bedarfsschätzung aus Gewichtstrend und erfasster Energieaufnahme (≈ 7’700 kcal pro kg Körpermasse).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Wichtiger Hinweis") {
                Text("Kern ist kein Medizinprodukt. Berechnungen, Analysen und KI-Vorschläge sind Schätzungen und ersetzen keine ärztliche, therapeutische oder ernährungsfachliche Beratung. Die 3D-Darstellung und Zielkörper sind illustrativ und keine Vorhersage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
