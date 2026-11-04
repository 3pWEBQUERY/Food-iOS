import Foundation
import SwiftData

/// Lebensmittel im lokalen Katalog (eigene Datenbank, Open Food Facts, eigene Einträge).
/// Nährwerte sind immer pro 100 g bzw. 100 ml angegeben.
@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String? = nil
    var barcode: String? = nil
    var category: String = ""
    var sourceRaw: String = FoodSource.user.rawValue
    var qualityRaw: String = DataQuality.community.rawValue
    var nutrientsData: Data = Data()
    var servingsData: Data = Data()
    var isLiquid: Bool = false
    var isFavorite: Bool = false
    var isHidden: Bool = false
    var useCount: Int = 0
    var lastUsedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Herkunfts-/Lizenzhinweis, z. B. ODbL für Open Food Facts.
    var licenseNote: String? = nil
    /// Externe ID bei der Quelle (z. B. OFF-Code, BLV-ID).
    var externalID: String? = nil
    /// Suchschlüssel in Kleinbuchstaben (Name + Marke + Synonyme).
    var searchKey: String = ""

    init(name: String, brand: String? = nil, barcode: String? = nil, category: String = "",
         source: FoodSource, quality: DataQuality, per100: Nutrients, servings: [ServingSize] = [],
         isLiquid: Bool = false, synonyms: [String] = []) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.category = category
        self.sourceRaw = source.rawValue
        self.qualityRaw = quality.rawValue
        self.nutrientsData = ModelCoding.encode(per100)
        self.servingsData = ModelCoding.encode(servings)
        self.isLiquid = isLiquid
        self.licenseNote = source.licenseNote
        self.searchKey = FoodItem.makeSearchKey(name: name, brand: brand, synonyms: synonyms)
    }

    var per100: Nutrients {
        get { ModelCoding.decode(Nutrients.self, from: nutrientsData, default: .zero) }
        set { nutrientsData = ModelCoding.encode(newValue); updatedAt = .now }
    }

    var servings: [ServingSize] {
        get { ModelCoding.decode([ServingSize].self, from: servingsData, default: []) }
        set { servingsData = ModelCoding.encode(newValue) }
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    var quality: DataQuality {
        get { DataQuality(rawValue: qualityRaw) ?? .community }
        set { qualityRaw = newValue.rawValue }
    }

    var unitSymbol: String { isLiquid ? "ml" : "g" }

    var displayName: String {
        if let brand, !brand.isEmpty { return "\(name) · \(brand)" }
        return name
    }

    static func makeSearchKey(name: String, brand: String?, synonyms: [String]) -> String {
        ([name, brand ?? ""] + synonyms)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale)
    }
}

/// Eintrag im Ernährungstagebuch. Speichert einen unveränderlichen Nährwert-
/// Schnappschuss (pro 100 g) zum Eintragszeitpunkt – spätere Korrekturen am
/// Katalog verändern historische Einträge nicht (Abschnitt 7.3).
@Model
final class FoodLogEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var dayKey: String = ""
    var mealRaw: String = MealType.snack.rawValue
    var foodID: UUID? = nil
    var recipeID: UUID? = nil
    var name: String = ""
    var brand: String? = nil
    /// Menge in Gramm bzw. Milliliter.
    var grams: Double = 100
    /// Anzeige der Menge, z. B. „1 Becher (180 g)“.
    var amountLabel: String = ""
    var per100Data: Data = Data()
    var qualityRaw: String = DataQuality.community.rawValue
    var sourceRaw: String = EntrySource.manual.rawValue
    /// KI-Schätzung – wird nie als exakt gemessen dargestellt.
    var isEstimate: Bool = false
    var isLiquid: Bool = false
    /// Verknüpfter Wassereintrag, falls das Getränk zur Flüssigkeit zählt.
    var linkedWaterEntryID: UUID? = nil
    var note: String = ""
    var healthKitSynced: Bool = false

    init(date: Date, meal: MealType, name: String, brand: String? = nil, grams: Double,
         amountLabel: String, per100: Nutrients, quality: DataQuality, source: EntrySource,
         foodID: UUID? = nil, recipeID: UUID? = nil, isEstimate: Bool = false, isLiquid: Bool = false) {
        self.date = date
        self.dayKey = DayKey.make(date)
        self.mealRaw = meal.rawValue
        self.name = name
        self.brand = brand
        self.grams = grams
        self.amountLabel = amountLabel
        self.per100Data = ModelCoding.encode(per100)
        self.qualityRaw = quality.rawValue
        self.sourceRaw = source.rawValue
        self.foodID = foodID
        self.recipeID = recipeID
        self.isEstimate = isEstimate
        self.isLiquid = isLiquid
    }

    /// Erstellt einen Eintrag aus einem Katalog-Lebensmittel.
    convenience init(food: FoodItem, grams: Double, amountLabel: String, meal: MealType, date: Date, source: EntrySource) {
        self.init(date: date, meal: meal, name: food.name, brand: food.brand, grams: grams,
                  amountLabel: amountLabel, per100: food.per100, quality: food.quality, source: source,
                  foodID: food.id, isEstimate: food.quality == .aiUnconfirmed, isLiquid: food.isLiquid)
    }

    var per100: Nutrients {
        get { ModelCoding.decode(Nutrients.self, from: per100Data, default: .zero) }
        set { per100Data = ModelCoding.encode(newValue) }
    }

    /// Nährwerte dieses Eintrags.
    var nutrients: Nutrients { per100.forGrams(grams) }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var quality: DataQuality { DataQuality(rawValue: qualityRaw) ?? .community }
    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    /// Verschiebt den Eintrag auf einen anderen Tag (Tagesschlüssel bleibt konsistent).
    func move(to newDate: Date) {
        date = newDate
        dayKey = DayKey.make(newDate)
    }
}

/// Eigenes Rezept. Nährwerte werden aus den Zutaten berechnet.
@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var servings: Int = 1
    /// Gewicht nach dem Kochen, falls bekannt – ermöglicht Werte pro 100 g.
    var cookedWeightG: Double? = nil
    var ingredientsData: Data = Data()
    var instructions: String = ""
    var isFavorite: Bool = false
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String, servings: Int = 1, ingredients: [MealComponent] = []) {
        self.name = name
        self.servings = servings
        self.ingredientsData = ModelCoding.encode(ingredients)
    }

    var ingredients: [MealComponent] {
        get { ModelCoding.decode([MealComponent].self, from: ingredientsData, default: []) }
        set { ingredientsData = ModelCoding.encode(newValue); updatedAt = .now }
    }

    var total: Nutrients { ingredients.reduce(Nutrients.zero) { $0 + $1.nutrients } }
    var rawWeightG: Double { ingredients.reduce(0) { $0 + $1.grams } }
    var perServing: Nutrients { total.scaled(by: 1 / Double(max(servings, 1))) }

    /// Gewicht einer Portion (gekochtes Gewicht, sonst Rohgewicht).
    var servingWeightG: Double { (cookedWeightG ?? rawWeightG) / Double(max(servings, 1)) }

    /// Werte pro 100 g, soweit berechenbar.
    var per100: Nutrients? {
        let weight = cookedWeightG ?? rawWeightG
        guard weight > 0 else { return nil }
        return total.scaled(by: 100 / weight)
    }
}

/// Gespeicherte Mahlzeitenkombination zum schnellen Wiederverwenden.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var mealRaw: String = MealType.breakfast.rawValue
    var itemsData: Data = Data()
    var useCount: Int = 0
    var createdAt: Date = Date()
    var lastUsedAt: Date? = nil

    init(name: String, meal: MealType, items: [MealComponent]) {
        self.name = name
        self.mealRaw = meal.rawValue
        self.itemsData = ModelCoding.encode(items)
    }

    var items: [MealComponent] {
        get { ModelCoding.decode([MealComponent].self, from: itemsData, default: []) }
        set { itemsData = ModelCoding.encode(newValue) }
    }

    var meal: MealType { MealType(rawValue: mealRaw) ?? .snack }
    var total: Nutrients { items.reduce(Nutrients.zero) { $0 + $1.nutrients } }
}

/// Flüssigkeitseintrag.
@Model
final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var dayKey: String = ""
    var ml: Double = 0
    var beverage: String = "Wasser"
    /// Verknüpfter Ernährungseintrag bei nährstoffhaltigen Getränken.
    var linkedFoodEntryID: UUID? = nil
    var sourceRaw: String = EntrySource.manual.rawValue
    var healthKitSynced: Bool = false

    init(ml: Double, date: Date = .now, beverage: String = "Wasser", source: EntrySource = .manual) {
        self.ml = ml
        self.date = date
        self.dayKey = DayKey.make(date)
        self.beverage = beverage
        self.sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
}
