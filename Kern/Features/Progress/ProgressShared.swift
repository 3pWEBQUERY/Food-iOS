import SwiftUI
import SwiftData
import LocalAuthentication

// MARK: - Datenzugriff

/// Gemeinsame Abfragen für Fortschritt, Analysen und Karten.
@MainActor
enum ProgressData {
    /// Alle Gewichtsmessungen, älteste zuerst.
    static func weights(in context: ModelContext) -> [WeightEntry] {
        let descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func weightPoints(in context: ModelContext) -> [(date: Date, kg: Double)] {
        weights(in: context).map { (date: $0.date, kg: $0.kg) }
    }

    static func foodEntries(in context: ModelContext, from start: Date, to end: Date) -> [FoodLogEntry] {
        let descriptor = FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return (try? context.fetch(descriptor)) ?? []
    }

    static func waterEntries(in context: ModelContext, from start: Date, to end: Date) -> [WaterEntry] {
        let descriptor = FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Abgeschlossene Trainingseinheiten im Zeitraum.
    static func sessions(in context: ModelContext, from start: Date, to end: Date) -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { $0.isCompleted || $0.endedAt != nil }
    }

    /// Kalorien pro Tagesschlüssel.
    static func kcalByDay(_ entries: [FoodLogEntry]) -> [String: Double] {
        var result: [String: Double] = [:]
        for entry in entries { result[entry.dayKey, default: 0] += entry.nutrients.kcal }
        return result
    }

    static func intakeByDay(in context: ModelContext, days: Int, now: Date = .now) -> [String: Double] {
        let end = now.startOfDay.adding(days: 1)
        let start = end.adding(days: -days - 1)
        return kcalByDay(foodEntries(in: context, from: start, to: end))
    }

    /// Bester geschätzter 1RM je Übung und Gerät. Unterschiedliche Geräte werden
    /// bewusst getrennt, da ihre Gewichte nicht direkt vergleichbar sind.
    static func bestLifts(_ sessions: [WorkoutSession]) -> [String: (name: String, e1rm: Double)] {
        var result: [String: (name: String, e1rm: Double)] = [:]
        for session in sessions {
            for log in session.exercises {
                guard let best = log.bestEstimatedOneRepMax, best > 0 else { continue }
                let key = "\(log.exerciseID)|\(log.equipmentID ?? "")"
                let label = log.equipmentLabel.map { "\(log.exerciseName) (\($0))" } ?? log.exerciseName
                if let current = result[key], current.e1rm >= best { continue }
                result[key] = (label, best)
            }
        }
        return result
    }

    /// Vergleicht Kraftwerte zwischen zwei Zeiträumen (nur gleiche Übung + gleiches Gerät).
    static func liftComparison(recent: [WorkoutSession], before: [WorkoutSession]) -> (improved: [String], declined: [String]) {
        let now = bestLifts(recent)
        let then = bestLifts(before)
        var improved: [String] = []
        var declined: [String] = []
        for (key, value) in now {
            guard let old = then[key] else { continue }
            if value.e1rm > old.e1rm * 1.005 { improved.append(value.name) }
            else if value.e1rm < old.e1rm * 0.97 { declined.append(value.name) }
        }
        return (improved.sorted(), declined.sorted())
    }
}

/// Datenpunkt für Diagramme.
struct ProgressChartPoint: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var value: Double
}

/// Zeitraum-Auswahl für Diagramme.
enum ProgressRange: String, CaseIterable, Identifiable {
    case month, quarter, half, year, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "1M"
        case .quarter: "3M"
        case .half: "6M"
        case .year: "1J"
        case .all: "Alle"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .month: "Ein Monat"
        case .quarter: "Drei Monate"
        case .half: "Sechs Monate"
        case .year: "Ein Jahr"
        case .all: "Gesamter Zeitraum"
        }
    }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .month: return cal.date(byAdding: .month, value: -1, to: .now)
        case .quarter: return cal.date(byAdding: .month, value: -3, to: .now)
        case .half: return cal.date(byAdding: .month, value: -6, to: .now)
        case .year: return cal.date(byAdding: .year, value: -1, to: .now)
        case .all: return nil
        }
    }
}

// MARK: - Schutz sensibler Bereiche

/// Schützt sensible Inhalte (Zyklus, Fotos) mit Face ID / Code, falls aktiviert.
struct ProgressSensitiveGate<Content: View>: View {
    let isRequired: Bool
    let reason: String
    @ViewBuilder var content: Content

    @State private var isUnlocked = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if !isRequired || isUnlocked {
                content
            } else {
                VStack(spacing: Theme.Space.m) {
                    Image(systemName: "lock")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Geschützter Bereich")
                        .font(.title3.weight(.semibold))
                    Text("Dieser Bereich enthält besonders sensible Daten und ist mit Face ID oder deinem Gerätecode geschützt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                    Button("Entsperren") { Task { await authenticate() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .task { await authenticate() }
            }
        }
    }

    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Ohne eingerichteten Gerätecode ist kein Schutz möglich.
            errorText = "Auf diesem Gerät ist kein Code eingerichtet. Der Schutz kann nicht angewendet werden."
            isUnlocked = true
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = success
        } catch {
            errorText = "Entsperren abgebrochen."
        }
    }
}

// MARK: - Kleine Bausteine

/// Navigationszeile innerhalb einer Card.
struct ProgressLinkRow: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var tint: Color = Theme.accent
    let destination: AppDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack {
                RowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

extension WeightEntry {
    var sourceSymbol: String {
        switch source {
        case .health: "heart"
        case .coach: "bubble.left.and.text.bubble.right"
        case .widget: "square.grid.2x2"
        default: "hand.tap"
        }
    }
}
