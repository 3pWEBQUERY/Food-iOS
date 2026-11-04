import Foundation
import SwiftData

enum SupplementForm: String, Codable, CaseIterable, Identifiable {
    case capsule, tablet, powder, liquid, gummy, drops, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .capsule: "Kapsel"
        case .tablet: "Tablette"
        case .powder: "Pulver"
        case .liquid: "Flüssig"
        case .gummy: "Gummy"
        case .drops: "Tropfen"
        case .other: "Andere"
        }
    }
    var symbol: String {
        switch self {
        case .capsule: "capsule"
        case .tablet: "pills"
        case .powder: "takeoutbag.and.cup.and.straw"
        case .liquid: "drop"
        case .gummy: "seal"
        case .drops: "eyedropper"
        case .other: "circle"
        }
    }
}

enum SupplementFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, specificDays, asNeeded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: "Täglich"
        case .specificDays: "An bestimmten Tagen"
        case .asNeeded: "Nach Bedarf"
        }
    }
}

/// Inhaltsstoff pro Portion.
struct SupplementIngredient: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: Double
    var unit: String   // mg, µg, g, IE
}

/// Supplement inkl. persönlicher Routine. Die App gibt keine Dosierungsempfehlungen –
/// dokumentiert wird ausschliesslich, was der Nutzer selbst festlegt.
@Model
final class Supplement {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var barcode: String? = nil
    var formRaw: String = SupplementForm.capsule.rawValue
    /// Portionsangabe laut Etikett, z. B. „2 Kapseln“.
    var servingLabel: String = "1 Portion"
    var ingredientsData: Data = Data()
    var qualityRaw: String = DataQuality.community.rawValue
    var sourceRaw: String = FoodSource.user.rawValue
    /// Verweis auf geprüfte Fachinformation (z. B. Behörde, Fachgesellschaft).
    var infoURL: String? = nil
    var notes: String = ""

    // Routine
    var isActive: Bool = true
    var frequencyRaw: String = SupplementFrequency.daily.rawValue
    /// Wochentage (1 = Sonntag … 7 = Samstag, wie `Calendar`).
    var weekdays: [Int] = []
    /// Einnahmezeitpunkte in Minuten seit Mitternacht.
    var scheduleMinutes: [Int] = [480]
    /// Vom Nutzer festgelegte Menge pro Einnahme (in Portionen).
    var servingsPerIntake: Double = 1
    var remindersEnabled: Bool = false

    // Vorrat
    var stockServings: Double? = nil
    var lowStockThreshold: Double = 7

    var createdAt: Date = Date()

    init(name: String, brand: String = "", form: SupplementForm = .capsule, servingLabel: String = "1 Portion",
         ingredients: [SupplementIngredient] = []) {
        self.name = name
        self.brand = brand
        self.formRaw = form.rawValue
        self.servingLabel = servingLabel
        self.ingredientsData = ModelCoding.encode(ingredients)
    }

    var ingredients: [SupplementIngredient] {
        get { ModelCoding.decode([SupplementIngredient].self, from: ingredientsData, default: []) }
        set { ingredientsData = ModelCoding.encode(newValue) }
    }

    var form: SupplementForm {
        get { SupplementForm(rawValue: formRaw) ?? .other }
        set { formRaw = newValue.rawValue }
    }

    var frequency: SupplementFrequency {
        get { SupplementFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    var quality: DataQuality { DataQuality(rawValue: qualityRaw) ?? .community }

    var isLowOnStock: Bool {
        guard let stockServings else { return false }
        return stockServings <= lowStockThreshold
    }

    /// Ist das Supplement am angegebenen Tag eingeplant?
    func isScheduled(on date: Date) -> Bool {
        guard isActive else { return false }
        switch frequency {
        case .daily: return true
        case .asNeeded: return false
        case .specificDays: return weekdays.contains(Calendar.current.component(.weekday, from: date))
        }
    }
}

@Model
final class SupplementIntake {
    var id: UUID = UUID()
    var supplementID: UUID = UUID()
    var supplementName: String = ""
    var date: Date = Date()
    var dayKey: String = ""
    var servings: Double = 1
    var scheduledMinute: Int? = nil
    var sourceRaw: String = EntrySource.manual.rawValue

    init(supplement: Supplement, servings: Double, date: Date = .now, scheduledMinute: Int? = nil, source: EntrySource = .manual) {
        self.supplementID = supplement.id
        self.supplementName = supplement.name
        self.servings = servings
        self.date = date
        self.dayKey = DayKey.make(date)
        self.scheduledMinute = scheduledMinute
        self.sourceRaw = source.rawValue
    }
}
