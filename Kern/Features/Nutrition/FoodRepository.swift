import Foundation
import SwiftData

// MARK: - Produktdaten aus externen Quellen

/// Neutraler Produktdatensatz aus Backend oder Open Food Facts (noch nicht im Katalog).
struct NutritionProductDTO: Hashable, Identifiable, Sendable {
    var id: String { barcode ?? name }
    var name: String
    var brand: String?
    var barcode: String?
    var per100: Nutrients
    var servingLabel: String?
    var servingGrams: Double?
    var isLiquid: Bool
    var source: FoodSource
    var quality: DataQuality
}

enum FoodLookupOrigin {
    case local, kernCatalog, openFoodFacts

    var title: String {
        switch self {
        case .local: "Aus deinem Katalog"
        case .kernCatalog: "Kern Katalog"
        case .openFoodFacts: "Open Food Facts"
        }
    }
}

enum FoodLookupResult {
    case found(FoodItem, FoodLookupOrigin)
    case notFound(String)
    case failed(String)
}

// MARK: - Open Food Facts

/// Zugriff auf Open Food Facts (ODbL). Daten gelten als Community-Einträge.
enum OpenFoodFactsClient {
    static let userAgent = "Kern-iOS/1.0 (iOS; Ernährungstagebuch)"
    private static let fields = "code,product_name,product_name_de,brands,nutriments,serving_size,serving_quantity,quantity"

    static func product(barcode: String) async throws -> NutritionProductDTO? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)") else { return nil }
        let json = try await fetchJSON(url)
        guard (json["status"] as? NSNumber)?.intValue == 1 || json["product"] != nil,
              let product = json["product"] as? [String: Any] else { return nil }
        return parse(product: product, fallbackCode: barcode)
    }

    static func search(_ query: String) async throws -> [NutritionProductDTO] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "lc", value: "de"),
            URLQueryItem(name: "fields", value: fields)
        ]
        guard let url = components?.url else { return [] }
        let json = try await fetchJSON(url)
        let products = json["products"] as? [[String: Any]] ?? []
        return products.compactMap { parse(product: $0, fallbackCode: nil) }
    }

    private static func fetchJSON(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return [:] }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            return Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    static func parse(product p: [String: Any], fallbackCode: String?) -> NutritionProductDTO? {
        let nameDE = (p["product_name_de"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nameAny = (p["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = nameDE.isEmpty ? nameAny : nameDE
        guard !name.isEmpty else { return nil }

        let n = p["nutriments"] as? [String: Any] ?? [:]
        func v(_ key: String) -> Double? { number(n[key]) }

        let kcal = v("energy-kcal_100g") ?? v("energy_100g").map { $0 / 4.184 }
        let protein = v("proteins_100g")
        let carbs = v("carbohydrates_100g")
        let fat = v("fat_100g")
        let salt = v("salt_100g") ?? v("sodium_100g").map { $0 * 2.5 }

        let nutrients = Nutrients(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0,
                                  sugar: v("sugars_100g"), saturatedFat: v("saturated-fat_100g"),
                                  fiber: v("fiber_100g"), salt: salt,
                                  calciumMg: v("calcium_100g").map { $0 * 1000 },
                                  ironMg: v("iron_100g").map { $0 * 1000 },
                                  magnesiumMg: v("magnesium_100g").map { $0 * 1000 },
                                  potassiumMg: v("potassium_100g").map { $0 * 1000 },
                                  vitaminCMg: v("vitamin-c_100g").map { $0 * 1000 },
                                  caffeineMg: v("caffeine_100g").map { $0 * 1000 })

        let keyMissing = kcal == nil || protein == nil || carbs == nil || fat == nil
        let quality: DataQuality = (keyMissing || !nutrients.isPlausible) ? .incomplete : .community

        let brand = (p["brands"] as? String)?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let quantity = ((p["quantity"] as? String) ?? "") + " " + ((p["serving_size"] as? String) ?? "")
        let lower = quantity.lowercased()
        let mentionsVolume = lower.contains("ml") || lower.contains("cl") || lower.contains(" l") || lower.contains("liter")
        let mentionsMass = lower.contains("kg") || lower.contains(" g") || lower.range(of: #"\dg"#, options: .regularExpression) != nil
        let isLiquid = mentionsVolume && !mentionsMass
        let servingGrams = number(p["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let servingLabel = (p["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return NutritionProductDTO(name: name, brand: (brand?.isEmpty ?? true) ? nil : brand,
                                   barcode: (p["code"] as? String) ?? fallbackCode,
                                   per100: nutrients, servingLabel: servingLabel, servingGrams: servingGrams,
                                   isLiquid: isLiquid, source: .openFoodFacts, quality: quality)
    }
}

// MARK: - Eigenes Backend

/// Optionaler eigener Katalog (Railway). Tolerantes Decoding, Fehler werden übersprungen.
enum KernCatalogClient {
    static func product(barcode: String, baseURL: String) async -> NutritionProductDTO? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/v1/foods/barcode/\(barcode)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainStore.get(KeychainStore.Keys.backendSession) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any] else { return nil }
        let p = (root["product"] as? [String: Any]) ?? root

        // Variante 1: OFF-ähnliches Format
        if p["nutriments"] != nil, var dto = OpenFoodFactsClient.parse(product: p, fallbackCode: barcode) {
            dto.source = .kernCatalog
            if let q = (p["quality"] as? String).flatMap(DataQuality.init(rawValue:)) { dto.quality = q }
            return dto
        }

        // Variante 2: eigenes Format
        guard let name = (p["name"] as? String) ?? (p["product_name"] as? String), !name.isEmpty else { return nil }
        let n = (p["per100"] as? [String: Any]) ?? (p["nutrients"] as? [String: Any]) ?? [:]
        func v(_ key: String) -> Double? { OpenFoodFactsClient.number(n[key]) }
        let nutrients = Nutrients(kcal: v("kcal") ?? 0, protein: v("protein") ?? 0, carbs: v("carbs") ?? 0,
                                  fat: v("fat") ?? 0, sugar: v("sugar"), saturatedFat: v("saturatedFat"),
                                  fiber: v("fiber"), salt: v("salt"))
        let quality = (p["quality"] as? String).flatMap(DataQuality.init(rawValue:)) ?? .verified
        return NutritionProductDTO(name: name, brand: p["brand"] as? String, barcode: barcode, per100: nutrients,
                                   servingLabel: p["servingLabel"] as? String,
                                   servingGrams: OpenFoodFactsClient.number(p["servingGrams"]),
                                   isLiquid: (p["isLiquid"] as? Bool) ?? false,
                                   source: .kernCatalog, quality: quality)
    }
}

// MARK: - Repository

/// Lebensmittel-Zugriff: lokale Datenbank → eigener Katalog → Open Food Facts (Abschnitt 7.1).
@MainActor
enum FoodRepository {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Fmt.locale).lowercased()
    }

    static func localFood(barcode: String, in context: ModelContext) -> FoodItem? {
        let code = barcode
        var descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == code })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Vollständige Abfragekette für einen Barcode.
    static func lookup(barcode raw: String, prefs: AppPreferences, in context: ModelContext) async -> FoodLookupResult {
        let barcode = raw.filter(\.isNumber)
        guard barcode.count >= 6 else { return .failed("Der Barcode ist ungültig.") }

        if let local = localFood(barcode: barcode, in: context) {
            return .found(local, .local)
        }
        if prefs.hasBackend, let dto = await KernCatalogClient.product(barcode: barcode, baseURL: prefs.backendBaseURL) {
            return .found(insert(dto, in: context), .kernCatalog)
        }
        do {
            if let dto = try await OpenFoodFactsClient.product(barcode: barcode) {
                return .found(insert(dto, in: context), .openFoodFacts)
            }
            return .notFound(barcode)
        } catch {
            return .failed("Keine Verbindung zu Open Food Facts. Prüfe deine Internetverbindung oder erfasse das Produkt manuell.")
        }
    }

    /// Übernimmt ein externes Produkt in den lokalen Katalog (oder liefert den vorhandenen Eintrag).
    @discardableResult
    static func insert(_ dto: NutritionProductDTO, in context: ModelContext) -> FoodItem {
        if let code = dto.barcode, let existing = localFood(barcode: code, in: context) {
            return existing
        }
        var servings: [ServingSize] = []
        if let grams = dto.servingGrams {
            servings.append(ServingSize(label: dto.servingLabel.map { "1 Portion (\($0))" } ?? "1 Portion", grams: grams))
        }
        let item = FoodItem(name: dto.name, brand: dto.brand, barcode: dto.barcode, category: "",
                            source: dto.source, quality: dto.quality, per100: dto.per100,
                            servings: servings, isLiquid: dto.isLiquid)
        item.externalID = dto.barcode
        context.insert(item)
        AuditLog.record(context, actor: .system, summary: "\(dto.name) aus \(dto.source.title) übernommen",
                        detail: dto.source.licenseNote ?? "", entityType: "FoodItem", entityID: item.id.uuidString)
        context.saveQuietly()
        return item
    }

    /// Lokale Suche mit Ranking (Präfix-Treffer, Nutzungshäufigkeit, Favoriten).
    static func search(_ foods: [FoodItem], query: String, limit: Int = 60) -> [FoodItem] {
        let terms = fold(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard let first = terms.first else { return [] }
        let joined = terms.joined(separator: " ")
        var scored: [(FoodItem, Double)] = []
        for food in foods {
            let key = food.searchKey.lowercased()
            guard terms.allSatisfy({ key.contains($0) }) else { continue }
            let name = fold(food.name)
            var score = 0.0
            if name == joined { score += 100 }
            if name.hasPrefix(first) {
                score += 40
            } else if name.split(separator: " ").contains(where: { $0.hasPrefix(first) }) {
                score += 20
            } else if !name.contains(first) {
                score -= 10 // nur über Synonym oder Marke gefunden
            }
            score += min(Double(food.useCount), 30) * 2
            if food.isFavorite { score += 25 }
            if food.quality == .verified { score += 5 }
            score -= Double(name.count) * 0.1
            scored.append((food, score))
        }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(limit)).map { $0.0 }
    }
}

// MARK: - Qualitäts-Helfer

enum NutritionQuality {
    private static func rank(_ q: DataQuality) -> Int {
        switch q {
        case .verified: 0
        case .manufacturer: 1
        case .reference: 2
        case .community: 3
        case .incomplete: 4
        case .aiUnconfirmed: 5
        }
    }

    /// Schlechteste Qualität einer Zusammenstellung (z. B. für Rezepte).
    static func worst(_ qualities: [DataQuality]) -> DataQuality {
        qualities.max { rank($0) < rank($1) } ?? .community
    }
}

// MARK: - Mahlzeiten- und Kopier-Helfer

@MainActor
enum NutritionMealLogger {
    /// Fügt alle Bestandteile einer gespeicherten Mahlzeit hinzu.
    static func log(_ saved: SavedMeal, meal: MealType, day: Date, in context: ModelContext) {
        let date = day.withCurrentTime()
        for component in saved.items {
            LogService.logCustom(name: component.name, nutrients: component.nutrients, grams: component.grams,
                                 amountLabel: "\(Fmt.number(component.grams)) g", meal: meal, date: date,
                                 quality: component.quality, source: .savedMeal,
                                 isEstimate: component.quality == .aiUnconfirmed, in: context)
        }
        saved.useCount += 1
        saved.lastUsedAt = .now
        context.saveQuietly()
    }

    /// Fügt Portionen eines Rezepts hinzu.
    static func log(_ recipe: Recipe, portions: Double, meal: MealType, day: Date, in context: ModelContext) {
        let quality = NutritionQuality.worst(recipe.ingredients.map(\.quality))
        let portionText = portions == 1 ? "1 Portion" : "\(Fmt.decimal(portions, maxDigits: 2)) Portionen"
        let grams = max(recipe.servingWeightG * portions, 1)
        let entry = LogService.logCustom(name: recipe.name, nutrients: recipe.perServing.scaled(by: portions),
                                         grams: grams, amountLabel: "\(portionText) (\(Fmt.number(grams)) g)",
                                         meal: meal, date: day.withCurrentTime(), quality: quality,
                                         source: .recipe, isEstimate: quality == .aiUnconfirmed, in: context)
        entry.recipeID = recipe.id
        recipe.useCount += 1
        context.saveQuietly()
    }

    /// Schnappschuss eines Tagebucheintrags als Bestandteil (für gespeicherte Mahlzeiten).
    static func component(from entry: FoodLogEntry) -> MealComponent {
        MealComponent(foodID: entry.foodID, name: entry.name, brand: entry.brand, grams: entry.grams,
                      per100: entry.per100, qualityRaw: entry.qualityRaw)
    }

    /// Kopiert einen Eintrag (z. B. „Nochmals hinzufügen“ oder „Tag kopieren“).
    @discardableResult
    static func copy(_ entry: FoodLogEntry, to date: Date, meal: MealType? = nil, in context: ModelContext) -> FoodLogEntry {
        let copy = FoodLogEntry(date: date, meal: meal ?? entry.meal, name: entry.name, brand: entry.brand,
                                grams: entry.grams, amountLabel: entry.amountLabel, per100: entry.per100,
                                quality: entry.quality, source: .copy, foodID: entry.foodID,
                                recipeID: entry.recipeID, isEstimate: entry.isEstimate, isLiquid: entry.isLiquid)
        context.insert(copy)
        return copy
    }

    /// Uhrzeit von `time` auf den Tag `day` übertragen.
    static func date(_ day: Date, keepingTimeOf time: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }
}
