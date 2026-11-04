import Foundation
import SwiftData

/// Gemeinsame Schreib-Operationen für Einträge. Wird von UI, Coach, Widgets und
/// Schnellaktionen genutzt, damit Protokoll, Apple Health und Widgets konsistent bleiben.
@MainActor
enum LogService {
    // MARK: Ernährung

    /// Erfasst ein Lebensmittel. Bei Getränken optional zusätzlich als Flüssigkeit (ohne Doppelerfassung).
    @discardableResult
    static func logFood(_ food: FoodItem, grams: Double, amountLabel: String, meal: MealType, date: Date,
                        source: EntrySource, countsAsWater: Bool = false, actor: AuditActor = .user,
                        in context: ModelContext) -> FoodLogEntry {
        let entry = FoodLogEntry(food: food, grams: grams, amountLabel: amountLabel, meal: meal, date: date, source: source)
        context.insert(entry)
        food.useCount += 1
        food.lastUsedAt = .now
        if countsAsWater && food.isLiquid {
            let water = WaterEntry(ml: grams, date: date, beverage: food.name, source: source)
            water.linkedFoodEntryID = entry.id
            entry.linkedWaterEntryID = water.id
            context.insert(water)
        }
        AuditLog.record(context, actor: actor, summary: "\(food.name) (\(amountLabel)) zu \(meal.title) hinzugefügt",
                        entityType: EntityType.food, entityID: entry.id.uuidString, undoable: true)
        finish(context)
        syncToHealth { await HealthKitManager.shared.saveNutrition(entry) }
        return entry
    }

    /// Erfasst einen freien Eintrag (z. B. Schnelleintrag oder Coach-Schätzung) ohne Katalogbezug.
    @discardableResult
    static func logCustom(name: String, nutrients: Nutrients, grams: Double = 100, amountLabel: String,
                          meal: MealType, date: Date, quality: DataQuality, source: EntrySource,
                          isEstimate: Bool, actor: AuditActor = .user, in context: ModelContext) -> FoodLogEntry {
        let per100 = grams > 0 ? nutrients.scaled(by: 100 / grams) : nutrients
        let entry = FoodLogEntry(date: date, meal: meal, name: name, grams: grams, amountLabel: amountLabel,
                                 per100: per100, quality: quality, source: source, isEstimate: isEstimate)
        context.insert(entry)
        AuditLog.record(context, actor: actor, summary: "\(name) zu \(meal.title) hinzugefügt",
                        entityType: EntityType.food, entityID: entry.id.uuidString, undoable: true)
        finish(context)
        syncToHealth { await HealthKitManager.shared.saveNutrition(entry) }
        return entry
    }

    static func deleteFood(_ entry: FoodLogEntry, actor: AuditActor = .user, in context: ModelContext) {
        if let waterID = entry.linkedWaterEntryID {
            let linked = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.id == waterID }))) ?? []
            linked.forEach { context.delete($0) }
        }
        AuditLog.record(context, actor: actor, summary: "\(entry.name) entfernt", entityType: EntityType.food,
                        entityID: entry.id.uuidString)
        context.delete(entry)
        finish(context)
    }

    // MARK: Wasser

    @discardableResult
    static func logWater(ml: Double, beverage: String = "Wasser", date: Date = .now, source: EntrySource = .manual,
                         actor: AuditActor = .user, in context: ModelContext) -> WaterEntry {
        let entry = WaterEntry(ml: ml, date: date, beverage: beverage, source: source)
        context.insert(entry)
        AuditLog.record(context, actor: actor, summary: "\(Fmt.volume(ml)) \(beverage) erfasst",
                        entityType: EntityType.water, entityID: entry.id.uuidString, undoable: true)
        finish(context)
        syncToHealth { await HealthKitManager.shared.saveWater(entry) }
        return entry
    }

    // MARK: Gewicht

    @discardableResult
    static func logWeight(kg: Double, date: Date = .now, source: EntrySource = .manual, note: String = "",
                          actor: AuditActor = .user, in context: ModelContext) -> WeightEntry {
        let entry = WeightEntry(kg: kg, date: date, source: source, note: note)
        context.insert(entry)
        AuditLog.record(context, actor: actor, summary: "Gewicht \(Fmt.decimal(kg, maxDigits: 1)) kg erfasst",
                        entityType: EntityType.weight, entityID: entry.id.uuidString, undoable: true)
        finish(context)
        syncToHealth { await HealthKitManager.shared.saveWeight(entry) }
        return entry
    }

    // MARK: Supplements

    @discardableResult
    static func logIntake(_ supplement: Supplement, servings: Double? = nil, date: Date = .now, scheduledMinute: Int? = nil,
                          source: EntrySource = .manual, actor: AuditActor = .user, in context: ModelContext) -> SupplementIntake {
        let amount = servings ?? supplement.servingsPerIntake
        let intake = SupplementIntake(supplement: supplement, servings: amount, date: date,
                                      scheduledMinute: scheduledMinute, source: source)
        context.insert(intake)
        if let stock = supplement.stockServings {
            supplement.stockServings = max(0, stock - amount)
        }
        AuditLog.record(context, actor: actor, summary: "\(supplement.name) eingenommen",
                        entityType: EntityType.supplementIntake, entityID: intake.id.uuidString, undoable: true)
        finish(context)
        return intake
    }

    // MARK: Rückgängig

    /// Macht eine protokollierte Erstellung rückgängig (löscht den erzeugten Eintrag).
    @discardableResult
    static func undo(_ log: AuditLogEntry, in context: ModelContext) -> Bool {
        guard log.isUndoable, !log.isUndone, let idString = log.entityID, let id = UUID(uuidString: idString) else { return false }
        var removed = false
        switch log.entityType {
        case EntityType.weight:
            let items = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id }))) ?? []
            removed = !items.isEmpty
            items.forEach { context.delete($0) }
        case EntityType.water:
            let items = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.id == id }))) ?? []
            removed = !items.isEmpty
            items.forEach { context.delete($0) }
        case EntityType.food:
            let items = (try? context.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.id == id }))) ?? []
            for item in items {
                if let waterID = item.linkedWaterEntryID {
                    let linked = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.id == waterID }))) ?? []
                    linked.forEach { context.delete($0) }
                }
                context.delete(item)
            }
            removed = !items.isEmpty
        case EntityType.supplementIntake:
            let items = (try? context.fetch(FetchDescriptor<SupplementIntake>(predicate: #Predicate { $0.id == id }))) ?? []
            for item in items {
                let supplementID = item.supplementID
                if let supplement = try? context.fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.id == supplementID })).first,
                   let stock = supplement.stockServings {
                    supplement.stockServings = stock + item.servings
                }
                context.delete(item)
            }
            removed = !items.isEmpty
        case EntityType.measurement:
            let items = (try? context.fetch(FetchDescriptor<BodyMeasurement>(predicate: #Predicate { $0.id == id }))) ?? []
            removed = !items.isEmpty
            items.forEach { context.delete($0) }
        default:
            return false
        }
        log.isUndone = true
        AuditLog.record(context, actor: .user, summary: "Rückgängig: \(log.summary)", entityType: log.entityType, entityID: log.entityID)
        finish(context)
        return removed
    }

    // MARK: Intern

    private static func finish(_ context: ModelContext) {
        context.saveQuietly()
        WidgetBridge.refresh(context: context)
    }

    private static func syncToHealth(_ work: @escaping @MainActor () async -> Void) {
        guard AppPreferences.shared.healthKitEnabled else { return }
        Task { @MainActor in await work() }
    }
}
