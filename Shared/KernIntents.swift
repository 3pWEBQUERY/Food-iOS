import AppIntents
import Foundation
import WidgetKit

/// Erfasst eine Trinkmenge direkt aus dem Widget. Läuft im Widget-Prozess: Die Menge
/// wird in die App Group geschrieben und beim nächsten App-Start als Eintrag übernommen.
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Wasser hinzufügen"
    static let description = IntentDescription("Erfasst eine Trinkmenge in Kern.")

    @Parameter(title: "Menge (ml)", default: 250)
    var ml: Int

    init() {}

    init(ml: Int) {
        self.ml = ml
    }

    func perform() async throws -> some IntentResult {
        let amount = Double(max(0, min(ml, 2000)))
        guard amount > 0 else { return .result() }
        WidgetPendingActions.appendWater(ml: amount)
        var snapshot = (WidgetSnapshot.load() ?? .empty).normalizedForToday()
        snapshot.waterMl += amount
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
