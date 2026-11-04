import Foundation
import UIKit
import Vision

/// Ergebnis der On-Device-Bildanalyse.
struct CoachImageAnalysis: Hashable {
    enum Kind: Hashable { case nutritionLabel, supplementLabel, food, unknown }

    var kind: Kind
    /// Erkannter Text (OCR).
    var text: String
    /// Klassifizierungen (englische Vision-Bezeichner) mit Konfidenz.
    var labels: [String]
    /// Aus einem Nährwertetikett gelesene Werte pro 100 g/ml.
    var kcalPer100: Double?
    var proteinPer100: Double?
    var carbsPer100: Double?
    var fatPer100: Double?
    var productName: String?

    /// Deutsche Suchbegriffe für erkannte Lebensmittel.
    var foodSearchTerms: [String] {
        labels.compactMap { CoachImageAnalyzer.foodTerms[$0] }
    }
}

/// Lokale Analyse über das Vision-Framework: Texterkennung und Bildklassifizierung.
/// Ergebnisse sind Vorschläge und werden immer als unbestätigte KI-Schätzung markiert.
enum CoachImageAnalyzer {
    static func analyze(_ data: Data) async -> CoachImageAnalysis {
        await Task.detached(priority: .userInitiated) {
            CoachImageAnalyzer.runAnalysis(data)
        }.value
    }

    private static func runAnalysis(_ data: Data) -> CoachImageAnalysis {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            return CoachImageAnalysis(kind: .unknown, text: "", labels: [])
        }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["de-DE", "fr-FR", "it-IT", "en-US"]
        textRequest.usesLanguageCorrection = true

        let classifyRequest = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textRequest, classifyRequest])

        let lines: [String] = (textRequest.results ?? []).compactMap { observation in
            (observation as? VNRecognizedTextObservation)?.topCandidates(1).first?.string
        }
        let text = lines.joined(separator: "\n")

        let labels: [String] = (classifyRequest.results ?? [])
            .compactMap { $0 as? VNClassificationObservation }
            .filter { $0.confidence > 0.25 }
            .prefix(8)
            .map(\.identifier)

        var analysis = CoachImageAnalysis(kind: .unknown, text: text, labels: Array(labels))
        let lower = text.lowercased()

        if lower.contains("kcal") || lower.contains("brennwert") || lower.contains("energie") {
            analysis.kind = .nutritionLabel
            analysis.kcalPer100 = kcal(in: lower)
            analysis.proteinPer100 = value(after: ["eiweiss", "eiweiß", "protein"], in: lower)
            analysis.carbsPer100 = value(after: ["kohlenhydrate", "glucides", "carboidrati"], in: lower)
            analysis.fatPer100 = value(after: ["fett", "matières grasses", "grassi"], in: lower)
            analysis.productName = lines.first { $0.count > 3 && $0.rangeOfCharacter(from: .decimalDigits) == nil }
        } else if ["kapsel", "tablette", "nahrungsergänzung", "nahrungsergaenzung", "vitamin", "tagesdosis", "verzehrempfehlung"]
                    .contains(where: { lower.contains($0) }) {
            analysis.kind = .supplementLabel
            analysis.productName = lines.first { $0.count > 3 }
        } else if !analysis.foodSearchTerms.isEmpty {
            analysis.kind = .food
        }
        return analysis
    }

    /// Erster kcal-Wert (pro 100 g steht auf Etiketten in der Regel zuerst).
    private static func kcal(in text: String) -> Double? {
        let pattern = #"(\d{1,4}(?:[.,]\d)?)\s*kcal"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private static func value(after keywords: [String], in text: String) -> Double? {
        for keyword in keywords {
            let pattern = NSRegularExpression.escapedPattern(for: keyword) + #"[^\d\n]{0,24}(\d{1,3}(?:[.,]\d{1,2})?)\s*g"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            if let v = Double(text[range].replacingOccurrences(of: ",", with: ".")) { return v }
        }
        return nil
    }

    /// Zuordnung ausgewählter Vision-Klassen zu deutschen Suchbegriffen.
    static let foodTerms: [String: String] = [
        "banana": "Banane", "apple": "Apfel", "orange": "Orange", "strawberry": "Erdbeere",
        "pizza": "Pizza", "salad": "Salat", "bread": "Brot", "sandwich": "Sandwich",
        "pasta": "Teigwaren", "spaghetti": "Spaghetti", "rice": "Reis", "egg": "Ei", "eggs": "Ei",
        "cheese": "Käse", "yogurt": "Joghurt", "oatmeal": "Haferflocken", "cereal": "Müesli",
        "chicken": "Poulet", "steak": "Rind", "fish": "Lachs", "salmon": "Lachs", "sushi": "Sushi",
        "burger": "Burger", "hamburger": "Burger", "fries": "Pommes", "french_fries": "Pommes",
        "potato": "Kartoffel", "broccoli": "Broccoli", "carrot": "Rüebli", "tomato": "Tomate",
        "avocado": "Avocado", "nuts": "Nüsse", "almond": "Mandeln", "chocolate": "Schokolade",
        "cake": "Kuchen", "croissant": "Gipfeli", "coffee": "Kaffee", "milk": "Milch", "soup": "Suppe"
    ]
}
