import Foundation
import SwiftData

/// Protokolliert Änderungen nachvollziehbar. Wird von manuellen Eingaben,
/// dem KI-Coach, Automatisierungen und der Health-Synchronisation genutzt.
enum AuditLog {
    @discardableResult
    static func record(_ context: ModelContext, actor: AuditActor, summary: String, detail: String = "",
                       entityType: String, entityID: String? = nil, undoable: Bool = false) -> AuditLogEntry {
        let entry = AuditLogEntry(actor: actor, summary: summary, detail: detail,
                                  entityType: entityType, entityID: entityID, isUndoable: undoable)
        context.insert(entry)
        return entry
    }
}

/// Bekannte Entitätstypen für Protokoll und Rückgängig-Funktion.
enum EntityType {
    static let weight = "WeightEntry"
    static let water = "WaterEntry"
    static let food = "FoodLogEntry"
    static let workout = "WorkoutSession"
    static let supplementIntake = "SupplementIntake"
    static let profile = "UserProfile"
    static let measurement = "BodyMeasurement"
    static let plan = "WorkoutPlan"
    static let cycle = "CycleDay"
    static let settings = "Settings"
}
