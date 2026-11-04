import SwiftUI
import SwiftData

/// Startseite gestalten: Karten anordnen, ausblenden und hinzufügen.
struct DashboardEditorView: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    private var hidden: [DashboardCardKind] {
        DashboardCardKind.allCases.filter { !prefs.dashboardCards.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(prefs.dashboardCards) { kind in
                        row(kind, isVisible: true)
                    }
                    .onMove { source, destination in
                        prefs.dashboardCards.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        prefs.dashboardCards.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Auf der Startseite")
                } footer: {
                    Text("Ziehen zum Anordnen. Karten von deaktivierten Modulen werden nicht angezeigt.")
                }

                if !hidden.isEmpty {
                    Section("Weitere Karten") {
                        ForEach(hidden) { kind in
                            row(kind, isVisible: false)
                        }
                    }
                }

                Section {
                    Button("Für mein Ziel zurücksetzen") {
                        let goal = profiles.first?.primaryGoal ?? .healthierLife
                        withAnimation { prefs.dashboardCards = DashboardCardKind.defaults(for: goal) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Startseite anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func row(_ kind: DashboardCardKind, isVisible: Bool) -> some View {
        let moduleOff = kind.requiredModule.map { !prefs.isEnabled($0) } ?? false
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: kind.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(moduleOff ? Color.secondary : Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                if moduleOff, let module = kind.requiredModule {
                    Text("Modul „\(module.title)“ ist deaktiviert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if moduleOff, let module = kind.requiredModule {
                Button("Aktivieren") { prefs.setModule(module, enabled: true) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            if !isVisible {
                Button {
                    withAnimation { prefs.dashboardCards.append(kind) }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(kind.title) hinzufügen")
            }
        }
    }
}
