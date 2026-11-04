import Foundation
import SwiftData
import UserNotifications

/// Beschreibende Zyklusstatistik. Alle Vorhersagen sind Schätzungen.
struct CycleStats {
    var periodStarts: [Date]
    var averageLength: Double?
    var lastLength: Int?
    var expectedLength: Int
    var nextPeriodEstimate: Date?
    var currentCycleDay: Int?
    var usesDefaultLength: Bool

    /// Tage bis zum geschätzten Beginn (negativ = Schätzung liegt in der Vergangenheit).
    func daysUntilNextPeriod(from now: Date = .now) -> Int? {
        guard let next = nextPeriodEstimate else { return nil }
        return Calendar.current.dateComponents([.day], from: now.startOfDay, to: next.startOfDay).day
    }
}

@MainActor
enum CycleCalculator {
    /// Perioden-Beginne: Blutungstage, denen mindestens zwei blutungsfreie Tage vorausgehen.
    static func periodStarts(_ days: [CycleDay]) -> [Date] {
        let bleeding = days.filter { $0.flow.isBleeding }.map(\.date.startOfDay).sorted()
        var starts: [Date] = []
        var previous: Date?
        for date in bleeding {
            if let previous, let gap = Calendar.current.dateComponents([.day], from: previous, to: date).day, gap <= 2 {
                // gleiche Periode
            } else {
                starts.append(date)
            }
            previous = date
        }
        return starts
    }

    static func stats(_ days: [CycleDay], defaultLength: Int, now: Date = .now) -> CycleStats {
        let starts = periodStarts(days)
        let cal = Calendar.current
        var lengths: [Int] = []
        for (a, b) in zip(starts, starts.dropFirst()) {
            if let d = cal.dateComponents([.day], from: a, to: b).day, (15...60).contains(d) {
                lengths.append(d)
            }
        }
        let recent = Array(lengths.suffix(6))
        let average = recent.isEmpty ? nil : Double(recent.reduce(0, +)) / Double(recent.count)
        let expected = average.map { Int($0.rounded()) } ?? defaultLength
        let last = starts.last
        let next = last.flatMap { cal.date(byAdding: .day, value: expected, to: $0) }
        let cycleDay = last.flatMap { start -> Int? in
            guard let d = cal.dateComponents([.day], from: start, to: now.startOfDay).day, d >= 0 else { return nil }
            return d + 1
        }
        return CycleStats(periodStarts: starts, averageLength: average, lastLength: lengths.last,
                          expectedLength: expected, nextPeriodEstimate: next, currentCycleDay: cycleDay,
                          usesDefaultLength: average == nil)
    }

    /// Zyklustag (1-basiert) für ein Datum relativ zum letzten Beginn davor.
    static func cycleDay(for date: Date, starts: [Date]) -> Int? {
        guard let start = starts.last(where: { $0 <= date.startOfDay }),
              let d = Calendar.current.dateComponents([.day], from: start, to: date.startOfDay).day else { return nil }
        let day = d + 1
        return day <= 60 ? day : nil
    }

    /// Geschätzte Periodentage im angegebenen Zeitraum (nur Darstellung).
    static func predictedDays(stats: CycleStats, periodLength: Int) -> Set<String> {
        guard let next = stats.nextPeriodEstimate, next >= Date.now.startOfDay.adding(days: -3) else { return [] }
        var result = Set<String>()
        for cycle in 0..<3 {
            let start = next.adding(days: cycle * stats.expectedLength)
            for offset in 0..<max(periodLength, 1) {
                result.insert(DayKey.make(start.adding(days: offset)))
            }
        }
        return result
    }

    static func day(for date: Date, in context: ModelContext) -> CycleDay? {
        let key = DayKey.make(date)
        var d = FetchDescriptor<CycleDay>(predicate: #Predicate { $0.dayKey == key })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Setzt die Blutungsstärke eines Tages (legt den Tageseintrag bei Bedarf an).
    static func setFlow(_ flow: CycleFlow, on date: Date, in context: ModelContext) {
        let entry = day(for: date, in: context) ?? {
            let new = CycleDay(date: date)
            context.insert(new)
            return new
        }()
        entry.flow = flow
        AuditLog.record(context, actor: .user, summary: "Zykluseintrag aktualisiert", entityType: EntityType.cycle,
                        entityID: entry.id.uuidString)
        context.saveQuietly()
    }

    // MARK: Erinnerung

    static let reminderID = "cycle.next"

    /// Diskrete Erinnerung zwei Tage vor dem geschätzten Beginn (keine sensiblen Details im Text).
    static func updateReminder(enabled: Bool, stats: CycleStats) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard enabled, let next = stats.nextPeriodEstimate,
              let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: next.adding(days: -2)) else { return }
        let seconds = fire.timeIntervalSinceNow
        guard seconds > 60 else { return }
        Task {
            guard await NotificationManager.requestAuthorization() else { return }
            NotificationManager.scheduleOnce(id: reminderID, title: "Kern", body: "Kleine Erinnerung an deinen Eintrag im Zyklusmodul.", after: seconds)
        }
    }
}
