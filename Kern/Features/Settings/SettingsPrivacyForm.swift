import SwiftData
import SwiftUI

/// Datenschutz, Export und vollständige Löschung.
struct SettingsPrivacyForm: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    @State private var counts: [(title: String, symbol: String, count: Int)] = []
    @State private var jsonURL: URL?
    @State private var weightsURL: URL?
    @State private var foodURL: URL?
    @State private var exportError: String?
    @State private var showFirstConfirm = false
    @State private var showFinalConfirm = false

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                ForEach(counts, id: \.title) { item in
                    LabeledContent {
                        Text(Fmt.number(Double(item.count))).monospacedDigit()
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                    }
                }
            } header: {
                Text("Deine Daten auf diesem Gerät")
            } footer: {
                Text("Alle Daten werden lokal in einer durch iOS verschlüsselten Datenbank gespeichert. Übertragungen erfolgen ausschliesslich verschlüsselt (TLS).")
            }

            Section {
                Toggle("Serverseitige KI-Verarbeitung", isOn: $prefs.aiProcessingConsent)
                    .disabled(prefs.isGuestMode)
                if prefs.isEnabled(.cycle) {
                    Toggle("Zyklusdaten für Auswertungen", isOn: $prefs.cycleAnalysisConsent)
                }
                Toggle("Sensible Bereiche mit Face ID schützen", isOn: $prefs.lockSensitiveModules)
                Toggle("Apple Health", isOn: Binding(get: { prefs.healthKitEnabled }, set: { if !$0 { prefs.healthKitEnabled = false } }))
                    .disabled(!prefs.healthKitEnabled)
            } header: {
                Text("Freigaben")
            } footer: {
                Text("Jede Freigabe ist freiwillig und einzeln widerrufbar. Apple Health aktivierst du unter Apple Health.")
            }

            Section {
                exportRow(title: "Vollständiger Export (JSON)", url: jsonURL) {
                    jsonURL = try DataExporter.exportJSON(context: context, prefs: prefs)
                }
                exportRow(title: "Gewichtsverlauf (CSV)", url: weightsURL) {
                    weightsURL = try DataExporter.exportWeightsCSV(context: context)
                }
                exportRow(title: "Ernährungstagebuch (CSV)", url: foodURL) {
                    foodURL = try DataExporter.exportFoodCSV(context: context)
                }
                if let exportError {
                    Text(exportError).font(.footnote).foregroundStyle(Theme.warning)
                }
            } header: {
                Text("Datenexport")
            } footer: {
                Text("Der JSON-Export enthält alle Einträge, Pläne, Einstellungen und das Änderungsprotokoll. Fortschrittsfotos werden als Metadaten aufgeführt.")
            }

            Section("Deine Rechte") {
                Text("Kern richtet sich nach dem Schweizer Datenschutzgesetz (nDSG) und der EU-Datenschutz-Grundverordnung (DSGVO). Du hast jederzeit das Recht auf Auskunft, Export, Berichtigung und Löschung deiner Daten. Gesundheits-, Körper- und Zyklusdaten werden nie für personalisierte Werbung verwendet und nie verkauft.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Externe Dienste") {
                serviceRow("Open Food Facts", detail: "Abfrage von Produktdaten per Barcode oder Suche. Übertragen wird nur der Barcode bzw. Suchbegriff. Lizenz: ODbL.", symbol: "barcode")
                serviceRow("Apple Health", detail: "Nur nach deiner Freigabe. Daten bleiben bei Apple auf deinem Gerät bzw. in deiner iCloud.", symbol: "heart")
                serviceRow("Kern-Server & KI", detail: prefs.hasBackend
                           ? "Konfiguriert. Wird nur mit deiner Zustimmung für Coach-Anfragen und Fotoerkennung genutzt."
                           : "Nicht konfiguriert – alles läuft lokal.", symbol: "server.rack")
                serviceRow("Anmelden mit Apple", detail: "Optional. Kern erhält eine anonyme Kennung und, falls freigegeben, deinen Namen.", symbol: "apple.logo")
            }

            Section {
                Button(role: .destructive) {
                    showFirstConfirm = true
                } label: {
                    Label("Alle Daten löschen", systemImage: "trash")
                }
            } footer: {
                Text("Löscht alle Einträge, Pläne, Fotos, Einstellungen und Zugangsdaten unwiderruflich von diesem Gerät. In Apple Health gespeicherte Daten verwaltest du in der Health-App.")
            }
        }
        .onAppear(perform: loadCounts)
        .confirmationDialog("Alle Daten löschen?", isPresented: $showFirstConfirm, titleVisibility: .visible) {
            Button("Weiter", role: .destructive) {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    showFinalConfirm = true
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Erstelle vorher am besten einen Export.")
        }
        .alert("Wirklich unwiderruflich löschen?", isPresented: $showFinalConfirm) {
            Button("Endgültig löschen", role: .destructive) {
                router.dismissSheet()
                router.todayPath = []
                router.show(tab: .today)
                DataExporter.deleteAllData(context: context, prefs: prefs)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle deine Daten auf diesem Gerät werden gelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.")
        }
    }

    @ViewBuilder
    private func exportRow(title: String, url: URL?, create: @escaping () throws -> Void) -> some View {
        if let url {
            ShareLink(item: url) {
                Label("\(title) teilen", systemImage: "square.and.arrow.up")
            }
        } else {
            Button {
                do {
                    try create()
                    exportError = nil
                } catch {
                    exportError = error.localizedDescription
                }
            } label: {
                Label("\(title) erstellen", systemImage: "doc.badge.plus")
            }
        }
    }

    private func serviceRow(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }

    private func loadCounts() {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }
        var items: [(title: String, symbol: String, count: Int)] = [
            ("Ernährungseinträge", "fork.knife", count(FoodLogEntry.self)),
            ("Wassereinträge", "drop", count(WaterEntry.self)),
            ("Gewichtsmessungen", "scalemass", count(WeightEntry.self)),
            ("Körpermasse", "ruler", count(BodyMeasurement.self)),
            ("Trainingseinheiten", "dumbbell", count(WorkoutSession.self)),
            ("Supplement-Einnahmen", "pills", count(SupplementIntake.self)),
            ("Coach-Nachrichten", "bubble.left.and.text.bubble.right", count(CoachMessage.self)),
            ("Protokolleinträge", "clock.arrow.circlepath", count(AuditLogEntry.self))
        ]
        if prefs.isEnabled(.cycle) { items.append(("Zyklustage", "circle.dashed", count(CycleDay.self))) }
        if prefs.isEnabled(.progressPhotos) { items.append(("Fortschrittsfotos", "photo", count(ProgressPhoto.self))) }
        counts = items
    }
}
