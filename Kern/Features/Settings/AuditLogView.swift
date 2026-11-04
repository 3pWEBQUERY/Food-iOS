import SwiftData
import SwiftUI

/// Nachvollziehbares Protokoll aller Änderungen – mit Rückgängig-Funktion, wo sinnvoll.
struct AuditLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AuditLogEntry.date, order: .reverse) private var entries: [AuditLogEntry]
    @State private var actorFilter: AuditActor?

    private var filtered: [AuditLogEntry] {
        guard let actorFilter else { return entries }
        return entries.filter { $0.actor == actorFilter }
    }

    private var days: [AuditLogDay] {
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfDay }
        return grouped.keys.sorted(by: >).map { AuditLogDay(day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "Noch keine Änderungen",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Hier siehst du, wann welche Daten von dir, dem Coach oder Apple Health geändert wurden.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    Text("Einträge, die erstellt wurden, kannst du hier rückgängig machen. Gelöschte Daten lassen sich nicht wiederherstellen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(days) { group in
                    Section(Fmt.day(group.day)) {
                        ForEach(group.entries) { entry in
                            AuditLogRow(entry: entry) {
                                _ = LogService.undo(entry, in: context)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Änderungsprotokoll")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $actorFilter) {
                        Text("Alle").tag(AuditActor?.none)
                        ForEach(AuditActor.allCases, id: \.self) { actor in
                            Label(actor.title, systemImage: actor.symbol).tag(AuditActor?.some(actor))
                        }
                    }
                } label: {
                    Image(systemName: actorFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filtern")
            }
        }
    }
}

private struct AuditLogDay: Identifiable {
    let day: Date
    let entries: [AuditLogEntry]
    var id: Date { day }
}

private struct AuditLogRow: View {
    let entry: AuditLogEntry
    let onUndo: () -> Void

    private var tint: Color {
        switch entry.actor {
        case .coach: Theme.accent
        case .health: Theme.fat
        case .automation: Theme.supplement
        case .user, .system: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.actor.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.summary)
                    .font(.subheadline)
                    .strikethrough(entry.isUndone, color: .secondary)
                    .foregroundStyle(entry.isUndone ? .secondary : .primary)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("\(Fmt.time(entry.date)) · \(entry.actor.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if entry.isUndone {
                Badge(text: "Rückgängig")
            } else if entry.isUndoable {
                Button("Rückgängig", action: onUndo)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .font(.footnote.weight(.medium))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
