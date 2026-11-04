import Foundation
import HealthKit
import Observation
import SwiftData

/// Apple-Health-Anbindung. Daten werden nur nach ausdrücklicher Freigabe ausgetauscht.
/// Duplikate werden über Sync-Identifier (eigene Samples) und Health-UUIDs (fremde Samples) verhindert.
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    @ObservationIgnored private let store = HKHealthStore()

    var todaySteps: Double?
    var todayActiveEnergyKcal: Double?
    var lastSyncAt: Date?
    var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKObjectType.workoutType()
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryWater),
            HKObjectType.workoutType()
        ]
    }

    /// Fragt die Berechtigungen an. Gibt `true` zurück, wenn der Dialog abgeschlossen wurde.
    func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastError = "Apple Health ist auf diesem Gerät nicht verfügbar."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Lesen

    func refreshToday() async {
        guard isAvailable else { return }
        let start = Date.now.startOfDay
        todaySteps = await sum(.stepCount, unit: .count(), from: start, to: .now)
        todayActiveEnergyKcal = await sum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: .now)
        lastSyncAt = .now
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        do {
            let result = try await descriptor.result(for: store)
            return result?.sumQuantity()?.doubleValue(for: unit)
        } catch {
            return nil
        }
    }

    /// Schritte pro Tag für die letzten `days` Tage (für Analysen).
    func dailySteps(days: Int) async -> [String: Double] {
        guard isAvailable else { return [:] }
        var result: [String: Double] = [:]
        for offset in 0..<days {
            let day = Date.now.adding(days: -offset).startOfDay
            let end = day.adding(days: 1)
            if let v = await sum(.stepCount, unit: .count(), from: day, to: end) {
                result[DayKey.make(day)] = v
            }
        }
        return result
    }

    /// Importiert Gewichtsmessungen anderer Apps/Waagen. Eigene Samples werden ignoriert,
    /// bereits importierte über ihre UUID erkannt.
    func importWeights(into context: ModelContext, days: Int = 60) async -> Int {
        guard isAvailable else { return 0 }
        let start = Date.now.adding(days: -days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200
        )
        do {
            let samples = try await descriptor.result(for: store)
            let ownBundle = Bundle.main.bundleIdentifier ?? ""
            let existing = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
            let knownUUIDs = Set(existing.compactMap(\.healthKitUUID))
            var imported = 0
            for sample in samples {
                if sample.sourceRevision.source.bundleIdentifier == ownBundle { continue }
                let uuid = sample.uuid.uuidString
                if knownUUIDs.contains(uuid) { continue }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                // Gleiche Messung bereits manuell erfasst? (±0.1 kg innerhalb von 30 Minuten)
                let duplicate = existing.contains { abs($0.kg - kg) < 0.1 && abs($0.date.timeIntervalSince(sample.startDate)) < 1800 }
                if duplicate { continue }
                let entry = WeightEntry(kg: kg, date: sample.startDate, source: .health)
                entry.healthKitUUID = uuid
                context.insert(entry)
                imported += 1
            }
            if imported > 0 {
                AuditLog.record(context, actor: .health, summary: "\(imported) Gewichtsmessung(en) aus Apple Health übernommen",
                                entityType: EntityType.weight)
                context.saveQuietly()
            }
            lastSyncAt = .now
            return imported
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    // MARK: Schreiben

    func saveWeight(_ entry: WeightEntry) async {
        guard isAvailable, entry.source != .health else { return }
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: entry.kg),
            start: entry.date, end: entry.date,
            metadata: syncMetadata(entry.id)
        )
        do {
            try await store.save(sample)
            entry.healthKitUUID = sample.uuid.uuidString
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveNutrition(_ entry: FoodLogEntry) async {
        guard isAvailable else { return }
        let n = entry.nutrients
        var samples: [HKQuantitySample] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double, suffix: String) {
            guard value > 0 else { return }
            var meta = syncMetadata(entry.id, suffix: suffix)
            meta[HKMetadataKeyFoodType] = entry.name
            samples.append(HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: entry.date, end: entry.date, metadata: meta))
        }
        add(.dietaryEnergyConsumed, .kilocalorie(), n.kcal, suffix: "kcal")
        add(.dietaryProtein, .gram(), n.protein, suffix: "protein")
        add(.dietaryCarbohydrates, .gram(), n.carbs, suffix: "carbs")
        add(.dietaryFatTotal, .gram(), n.fat, suffix: "fat")
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            entry.healthKitSynced = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveWater(_ entry: WaterEntry) async {
        guard isAvailable, entry.ml > 0 else { return }
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater),
                                      quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: entry.ml),
                                      start: entry.date, end: entry.date, metadata: syncMetadata(entry.id))
        do {
            try await store.save(sample)
            entry.healthKitSynced = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveWorkout(_ session: WorkoutSession) async {
        guard isAvailable, let end = session.endedAt else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            try await builder.addMetadata(syncMetadata(session.id))
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout() {
                session.healthKitUUID = workout.uuid.uuidString
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sync-Identifier sorgen dafür, dass Health Duplikate eigener Einträge ersetzt statt verdoppelt.
    private func syncMetadata(_ id: UUID, suffix: String = "") -> [String: Any] {
        [
            HKMetadataKeySyncIdentifier: "kern.\(id.uuidString)\(suffix.isEmpty ? "" : ".\(suffix)")",
            HKMetadataKeySyncVersion: 1
        ]
    }
}
