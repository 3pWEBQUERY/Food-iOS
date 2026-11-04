import Foundation

/// Hilfsfunktionen für die regelbasierte, deutschsprachige Spracherkennung des Coaches.
struct CoachText {
    let original: String
    /// Kleinbuchstaben, Umlaute bleiben erhalten.
    let lower: String
    /// Ohne Gross-/Kleinschreibung und Akzente (passend zu `FoodItem.searchKey`).
    let folded: String

    init(_ text: String) {
        original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lower = original.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "’", with: "'")
        folded = CoachText.fold(original)
    }

    var isEmpty: Bool { original.isEmpty }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_CH"))
            .replacingOccurrences(of: "ß", with: "ss")
    }

    func contains(_ word: String) -> Bool { lower.contains(word) }

    func containsAny(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }

    func firstMatch(_ word: [String]) -> String? { word.first { lower.contains($0) } }

    var isQuestion: Bool {
        original.contains("?") || containsAny(["was ", "wie ", "warum", "wieso", "weshalb", "erklär", "wann ", "welche"])
            || lower.hasPrefix("was") || lower.hasPrefix("wie")
    }

    // MARK: Regex

    /// Erste Übereinstimmung; liefert die Capture-Gruppen (fehlende Gruppen = nil).
    func groups(_ pattern: String) -> [String?]? {
        CoachText.groups(pattern, in: lower)
    }

    func allGroups(_ pattern: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(lower.startIndex..., in: lower)
        return regex.matches(in: lower, range: range).map { match in
            (1..<max(match.numberOfRanges, 1)).map { index in
                Range(match.range(at: index), in: lower).map { String(lower[$0]) }
            }
        }
    }

    static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<max(match.numberOfRanges, 1)).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    func matches(_ pattern: String) -> Bool {
        lower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Datum & Uhrzeit

    /// Tag aus „heute/gestern/vorgestern“ oder einem expliziten Datum (z. B. 3.11.).
    func day(now: Date) -> (key: String, isExplicit: Bool) {
        if contains("vorgestern") { return (DayKey.make(now.adding(days: -2)), true) }
        if contains("gestern") { return (DayKey.make(now.adding(days: -1)), true) }
        if let g = groups(#"(?<![\d,.])(\d{1,2})\.(\d{1,2})\.(\d{2,4})?"#),
           let d = g[0].flatMap({ Int($0) }), let m = g[1].flatMap({ Int($0) }), (1...31).contains(d), (1...12).contains(m) {
            let cal = Calendar.current
            var year = cal.component(.year, from: now)
            if let yText = g.count > 2 ? g[2] : nil, let y = Int(yText) {
                year = y < 100 ? 2000 + y : y
            }
            if var date = cal.date(from: DateComponents(year: year, month: m, day: d)) {
                if date > now, g.count < 3 || g[2] == nil {
                    date = cal.date(byAdding: .year, value: -1, to: date) ?? date
                }
                return (DayKey.make(date), true)
            }
        }
        return (DayKey.make(now), contains("heute"))
    }

    /// Uhrzeit nur, wenn sie ausdrücklich genannt wurde („um 7“, „07:30“, „8 Uhr“).
    var time: String? {
        if let g = groups(#"\b(\d{1,2}):(\d{2})\b"#), let h = g[0].flatMap({ Int($0) }), let m = g[1].flatMap({ Int($0) }),
           (0...23).contains(h), (0...59).contains(m) {
            return String(format: "%02d:%02d", h, m)
        }
        if let g = groups(#"\bum\s+(\d{1,2})(?:[.](\d{2}))?\b(?!\s*(?:kg|g|ml|l|kilo))"#), let h = g[0].flatMap({ Int($0) }), (0...23).contains(h) {
            let m = (g.count > 1 ? g[1] : nil).flatMap { Int($0) } ?? 0
            return String(format: "%02d:%02d", h, m)
        }
        if let g = groups(#"\b(\d{1,2})\s*uhr\b"#), let h = g[0].flatMap({ Int($0) }), (0...23).contains(h) {
            return String(format: "%02d:00", h)
        }
        return nil
    }

    // MARK: Mengen

    /// Volumenangabe in ml (ml, cl, dl, l).
    func volumeMl() -> Double? {
        guard let g = groups(#"(\d+(?:[.,]\d+)?)\s*(milliliter|ml|liter|dl|cl|l)\b"#),
              let value = CoachParam.double(g[0]), let unit = g.count > 1 ? g[1] : nil else { return nil }
        switch unit {
        case "liter", "l": return value * 1000
        case "dl": return value * 100
        case "cl": return value * 10
        default: return value
        }
    }

    static let numberWords: [String: Double] = [
        "ein": 1, "eine": 1, "einen": 1, "einem": 1, "einer": 1, "zwei": 2, "drei": 3, "vier": 4,
        "fünf": 5, "sechs": 6, "halbe": 0.5, "halben": 0.5, "halbes": 0.5
    ]

    static func count(from word: String?) -> Double? {
        guard let word else { return nil }
        if let n = Double(word.replacingOccurrences(of: ",", with: ".")) { return n }
        return numberWords[word]
    }

    /// Satzteile, getrennt an Satzzeichen (nicht in Dezimalzahlen wie 100,2).
    var clauses: [String] {
        original
            .replacingOccurrences(of: #"[,.;!?](?!\d)"#, with: "|", options: .regularExpression)
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
