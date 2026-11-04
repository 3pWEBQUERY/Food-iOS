import Foundation

/// Nährwerte. In `FoodItem` immer pro 100 g bzw. 100 ml.
/// Optionale Werte sind `nil`, wenn sie nicht bekannt sind (nicht 0!).
struct Nutrients: Codable, Hashable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var sugar: Double? = nil
    var saturatedFat: Double? = nil
    var fiber: Double? = nil
    var salt: Double? = nil
    // Mikronährstoffe (soweit verfügbar)
    var calciumMg: Double? = nil
    var ironMg: Double? = nil
    var magnesiumMg: Double? = nil
    var potassiumMg: Double? = nil
    var zincMg: Double? = nil
    var vitaminCMg: Double? = nil
    var vitaminDUg: Double? = nil
    var vitaminB12Ug: Double? = nil
    var caffeineMg: Double? = nil

    static let zero = Nutrients()

    init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
         sugar: Double? = nil, saturatedFat: Double? = nil, fiber: Double? = nil, salt: Double? = nil,
         calciumMg: Double? = nil, ironMg: Double? = nil, magnesiumMg: Double? = nil,
         potassiumMg: Double? = nil, zincMg: Double? = nil, vitaminCMg: Double? = nil,
         vitaminDUg: Double? = nil, vitaminB12Ug: Double? = nil, caffeineMg: Double? = nil) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.fiber = fiber
        self.salt = salt
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.magnesiumMg = magnesiumMg
        self.potassiumMg = potassiumMg
        self.zincMg = zincMg
        self.vitaminCMg = vitaminCMg
        self.vitaminDUg = vitaminDUg
        self.vitaminB12Ug = vitaminB12Ug
        self.caffeineMg = caffeineMg
    }

    /// Skaliert alle Werte (z. B. von 100 g auf eine Portion).
    func scaled(by factor: Double) -> Nutrients {
        func s(_ v: Double?) -> Double? { v.map { $0 * factor } }
        return Nutrients(
            kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
            sugar: s(sugar), saturatedFat: s(saturatedFat), fiber: s(fiber), salt: s(salt),
            calciumMg: s(calciumMg), ironMg: s(ironMg), magnesiumMg: s(magnesiumMg),
            potassiumMg: s(potassiumMg), zincMg: s(zincMg), vitaminCMg: s(vitaminCMg),
            vitaminDUg: s(vitaminDUg), vitaminB12Ug: s(vitaminB12Ug), caffeineMg: s(caffeineMg)
        )
    }

    /// Werte für eine Menge in Gramm, ausgehend von Werten pro 100 g.
    func forGrams(_ grams: Double) -> Nutrients { scaled(by: grams / 100) }

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        func a(_ x: Double?, _ y: Double?) -> Double? {
            if x == nil && y == nil { return nil }
            return (x ?? 0) + (y ?? 0)
        }
        return Nutrients(
            kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat,
            sugar: a(lhs.sugar, rhs.sugar), saturatedFat: a(lhs.saturatedFat, rhs.saturatedFat),
            fiber: a(lhs.fiber, rhs.fiber), salt: a(lhs.salt, rhs.salt),
            calciumMg: a(lhs.calciumMg, rhs.calciumMg), ironMg: a(lhs.ironMg, rhs.ironMg),
            magnesiumMg: a(lhs.magnesiumMg, rhs.magnesiumMg), potassiumMg: a(lhs.potassiumMg, rhs.potassiumMg),
            zincMg: a(lhs.zincMg, rhs.zincMg), vitaminCMg: a(lhs.vitaminCMg, rhs.vitaminCMg),
            vitaminDUg: a(lhs.vitaminDUg, rhs.vitaminDUg), vitaminB12Ug: a(lhs.vitaminB12Ug, rhs.vitaminB12Ug),
            caffeineMg: a(lhs.caffeineMg, rhs.caffeineMg)
        )
    }

    static func += (lhs: inout Nutrients, rhs: Nutrients) { lhs = lhs + rhs }

    /// Fehlen wesentliche Angaben (Zucker, Ballaststoffe, Salz)?
    var isIncomplete: Bool { sugar == nil || fiber == nil || salt == nil }

    /// Plausibilitätsprüfung: Energie aus Makros vs. angegebene Energie (Toleranz 25 %).
    var isPlausible: Bool {
        let fromMacros = protein * 4 + carbs * 4 + fat * 9 + (fiber ?? 0) * 2
        guard kcal > 20 else { return fromMacros < 40 }
        return abs(fromMacros - kcal) / kcal < 0.25
    }

    /// Liste vorhandener Mikronährstoffe für die Detailanzeige.
    var micronutrientRows: [(label: String, value: Double, unit: String)] {
        var rows: [(String, Double, String)] = []
        if let v = calciumMg { rows.append(("Calcium", v, "mg")) }
        if let v = ironMg { rows.append(("Eisen", v, "mg")) }
        if let v = magnesiumMg { rows.append(("Magnesium", v, "mg")) }
        if let v = potassiumMg { rows.append(("Kalium", v, "mg")) }
        if let v = zincMg { rows.append(("Zink", v, "mg")) }
        if let v = vitaminCMg { rows.append(("Vitamin C", v, "mg")) }
        if let v = vitaminDUg { rows.append(("Vitamin D", v, "µg")) }
        if let v = vitaminB12Ug { rows.append(("Vitamin B12", v, "µg")) }
        if let v = caffeineMg { rows.append(("Koffein", v, "mg")) }
        return rows.map { (label: $0.0, value: $0.1, unit: $0.2) }
    }
}

/// Portionsgrösse eines Lebensmittels.
struct ServingSize: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String       // z. B. „1 Becher“, „1 Scheibe“
    var grams: Double       // Gramm bzw. Milliliter
}

/// Bestandteil eines Rezepts oder einer gespeicherten Mahlzeit.
/// Enthält einen Nährwert-Schnappschuss, damit spätere Katalogänderungen
/// bestehende Rezepte nicht unbemerkt verändern.
struct MealComponent: Codable, Hashable, Identifiable {
    var id = UUID()
    var foodID: UUID?
    var name: String
    var brand: String?
    var grams: Double
    var per100: Nutrients
    var qualityRaw: String = DataQuality.reference.rawValue

    var nutrients: Nutrients { per100.forGrams(grams) }
    var quality: DataQuality { DataQuality(rawValue: qualityRaw) ?? .community }
}

// MARK: - JSON-Helfer für Data-gestützte Modell-Eigenschaften

enum ModelCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, default fallback: T) -> T {
        guard !data.isEmpty else { return fallback }
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }
}
