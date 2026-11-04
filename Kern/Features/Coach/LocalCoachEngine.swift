import Foundation
import SwiftData

/// Regelbasierter Coach, vollständig auf dem Gerät. Erkennt Absichten in Alltagssprache
/// und erstellt daraus strukturierte, prüfbare Aktionen. Erfindet keine Werte:
/// Fehlen Mengen, Uhrzeiten oder Zuordnungen, wird nachgefragt.
struct LocalCoachEngine: CoachEngine {
    @MainActor
    func respond(to input: CoachInput, context: CoachContext) async throws -> CoachReply {
        var worker = CoachLocalWorker(text: CoachText(input.text), context: context)
        return worker.run(image: input.imageAnalysis)
    }
}

@MainActor
private struct CoachLocalWorker {
    let text: CoachText
    let context: CoachContext
    var actions: [CoachAction] = []
    var lines: [String] = []
    var quickReplies: [String] = []

    init(text: CoachText, context: CoachContext) {
        self.text = text
        self.context = context
    }

    private var db: ModelContext { context.modelContext }
    private var now: Date { context.now }

    // MARK: Ablauf

    mutating func run(image: CoachImageAnalysis?) -> CoachReply {
        if let image { handleImage(image) }

        if text.isEmpty {
            if actions.isEmpty && lines.isEmpty { return helpReply() }
            return compose()
        }

        if let reply = medicalReply() { return reply }
        if text.containsAny(["lösch", "loesch", "entfern"]) { return deleteReply() }
        if let reply = explanationReply() { return reply }
        if let reply = weeklyReply() { return reply }
        if let reply = searchReply() { return reply }

        detectWaterTarget()
        detectWeight()
        detectFood()
        detectWater()
        detectSupplements()
        detectWorkoutNote()
        detectGoalChange()
        detectStartWorkout()
        if actions.isEmpty { detectNavigation() }

        if actions.isEmpty && lines.isEmpty { return helpReply() }
        return compose()
    }

    private func compose() -> CoachReply {
        var parts = lines
        let pending = actions.filter { $0.status == .needsInput }.count
        let proposed = actions.filter { $0.status == .proposed && !$0.isNavigation }.count
        if proposed == 1 {
            parts.append("Ich habe einen Eintrag vorbereitet. Bitte prüfe ihn und bestätige.")
        } else if proposed > 1 {
            parts.append("Ich habe \(proposed) Einträge vorbereitet. Du kannst sie einzeln prüfen und bestätigen.")
        }
        if pending > 0 {
            parts.append(pending == 1 ? "Eine Angabe fehlt noch – bitte wähle unten aus." : "Einige Angaben fehlen noch – bitte wähle unten aus.")
        }
        if parts.isEmpty, actions.contains(where: \.isNavigation) {
            parts.append("Hier entlang:")
        }
        return CoachReply(text: parts.joined(separator: "\n\n"), actions: actions, quickReplies: quickReplies)
    }

    private func helpReply() -> CoachReply {
        CoachReply(
            text: """
            Ich kann Einträge für dich vorbereiten, Bereiche öffnen und deine Daten erklären. Zum Beispiel:
            • „Heute 82,4 kg gewogen“
            • „500 ml Wasser getrunken“
            • „200 g Skyr zum Frühstück“
            • „Kreatin genommen“
            • „Wie war meine Woche?“
            • „Wo stelle ich das Wasserziel ein?“
            """,
            quickReplies: ["Wie war meine Woche?", "Was ist mein Grundumsatz?", "Was habe ich heute gegessen?"]
        )
    }

    // MARK: Sicherheit

    private func medicalReply() -> CoachReply? {
        let medical = ["diagnose", "diagnostizier", "medikament", "wechselwirkung", "bin ich krank", "krankheit",
                       "therapie", "behandlung", "brustschmerz", "herzrasen", "dosierung", "wie viel soll ich einnehmen"]
        guard text.containsAny(medical) else { return nil }
        return CoachReply(
            text: """
            Dabei kann ich dir nicht weiterhelfen: Ich stelle keine Diagnosen, beurteile keine Medikamente oder Wechselwirkungen \
            und gebe keine Dosierungsempfehlungen. Bitte wende dich an eine Ärztin, einen Arzt oder eine Apotheke. \
            Bei akuten Beschwerden ruf den Notruf 144 (Schweiz) bzw. 112 an.

            Was ich tun kann: deine Einträge dokumentieren und zeitliche Zusammenhänge sichtbar machen – ohne Ursachen zu behaupten.
            """,
            quickReplies: ["Wie war meine Woche?"]
        )
    }

    // MARK: Löschen (immer mit Bestätigung)

    private func deleteReply() -> CoachReply {
        if text.containsAny(["alle daten", "alles löschen", "konto löschen", "alle einträge"]) {
            var action = CoachAction(kind: .openSettings, title: "Datenschutz & Daten öffnen",
                                     detail: "Das vollständige Löschen ist nur dort mit doppelter Bestätigung möglich.")
            action.params[CoachParam.section] = SettingsSection.privacy.rawValue
            return CoachReply(text: "Alle Daten lösche ich nicht über den Chat. Das geht bewusst nur in den Datenschutz-Einstellungen.",
                              actions: [action])
        }
        if text.containsAny(["gewicht", "gewogen", "wiegen", "wägung"]) {
            var d = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            d.fetchLimit = 1
            guard let entry = try? db.fetch(d).first else {
                return CoachReply(text: "Ich habe keinen Gewichtseintrag gefunden.")
            }
            var action = CoachAction(kind: .deleteLastWeight, title: "Letzten Gewichtseintrag löschen",
                                     detail: "\(Fmt.weightWithUnit(entry.kg, unit: context.prefs.weightUnit)) · \(Fmt.day(entry.date)), \(Fmt.time(entry.date))",
                                     isDestructive: true)
            action.params[CoachParam.entityID] = entry.id.uuidString
            return CoachReply(text: "Soll ich diesen Eintrag löschen? Das musst du ausdrücklich bestätigen.", actions: [action])
        }
        if text.containsAny(["mahlzeit", "eintrag", "essen", "lebensmittel", "gegessen"]) {
            var d = FetchDescriptor<FoodLogEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            d.fetchLimit = 1
            guard let entry = try? db.fetch(d).first else {
                return CoachReply(text: "Ich habe keinen Ernährungseintrag gefunden.")
            }
            var action = CoachAction(kind: .deleteEntry, title: "Letzten Ernährungseintrag löschen",
                                     detail: "\(entry.name) · \(entry.amountLabel) · \(Fmt.day(entry.date))", isDestructive: true)
            action.params[CoachParam.entityID] = entry.id.uuidString
            return CoachReply(text: "Soll ich diesen Eintrag löschen? Das musst du ausdrücklich bestätigen.", actions: [action])
        }
        return CoachReply(text: "Was genau soll ich löschen?",
                          quickReplies: ["Lösche meinen letzten Gewichtseintrag", "Lösche meinen letzten Ernährungseintrag"])
    }

    // MARK: Erklärungen

    private func explanationReply() -> CoachReply? {
        let energyWords = ["grundumsatz", "tdee", "gesamtbedarf", "kalorienbedarf", "energiebedarf", "wie viele kalorien brauche",
                           "kalorienziel berechnet", "wie wird mein kalorienziel", "wie berechnest du"]
        if text.containsAny(energyWords), !text.containsAny(Self.navigationVerbs) {
            guard let profile = context.profile else { return CoachReply(text: "Dafür brauche ich dein Profil.") }
            let inputs = ProfileService.energyInputs(for: profile, in: db)
            let result = EnergyCalculator.compute(inputs, formula: profile.energyFormula, tdeeOverride: profile.adaptiveTDEE)
            var body = "So schätzt Kern deinen Energiebedarf:\n"
            body += result.explanation.map { "• \($0)" }.joined(separator: "\n")
            if !result.notes.isEmpty {
                body += "\n\n" + result.notes.map { "Hinweis: \($0.text)" }.joined(separator: "\n")
            }
            body += "\n\nDas sind Schätzungen nach etablierten Formeln, keine Messwerte. Mit vollständig erfassten Wochen und regelmässigen Wägungen wird die Schätzung schrittweise genauer."
            var insight = CoachAction(kind: .navigate, title: "Energiebedarf im Detail")
            insight.params[CoachParam.destination] = "energyInsight"
            var settings = CoachAction(kind: .openSettings, title: "Zielwerte anpassen")
            settings.params[CoachParam.section] = SettingsSection.targets.rawValue
            return CoachReply(text: body, actions: [insight, settings])
        }
        if text.containsAny(["rpe", "rir"]), text.isQuestion {
            return CoachReply(text: """
            RPE (Rate of Perceived Exertion) beschreibt, wie anstrengend sich ein Satz angefühlt hat – auf einer Skala von 1 bis 10. \
            RIR (Reps in Reserve) gibt an, wie viele Wiederholungen du noch geschafft hättest. RPE 8 entspricht etwa RIR 2.
            """)
        }
        return nil
    }

    // MARK: Wochenanalyse

    private func weeklyReply() -> CoachReply? {
        let words = ["wie war meine woche", "wochenanalyse", "wochenbericht", "wochenzusammenfassung", "wie lief meine woche",
                     "wie läuft es", "wie lauft es", "analysiere meine", "meine fortschritte", "wie entwickle ich mich"]
        guard text.containsAny(words), !text.containsAny(Self.navigationVerbs) else { return nil }
        guard let profile = context.profile else { return CoachReply(text: "Dafür brauche ich dein Profil.") }
        let report = InsightEngine.weeklyReport(in: db, profile: profile)
        var body = "\(report.periodTitle)\n\(report.headline)"
        if !report.items.isEmpty {
            body += "\n\n" + report.items.prefix(6).map { "• \($0.title): \($0.detail)" }.joined(separator: "\n")
        }
        body += "\n\nBeobachtungen zeigen zeitliche Zusammenhänge – sie belegen keine Ursachen."
        var open = CoachAction(kind: .navigate, title: "Ganze Wochenanalyse öffnen")
        open.params[CoachParam.destination] = "weeklyReport"
        return CoachReply(text: body, actions: [open], quickReplies: ["Was ist mein Grundumsatz?"])
    }

    // MARK: Suche in Einträgen

    private func searchReply() -> CoachReply? {
        // „Was habe ich gestern gegessen?“
        if text.containsAny(["was habe ich", "was hab ich", "was hatte ich"]), text.containsAny(["gegessen", "gefrühstückt", "zu mittag", "zu abend"]) {
            let day = text.day(now: now).key
            let entries = ((try? db.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.dayKey == day },
                                                                        sortBy: [SortDescriptor(\.date)]))) ?? [])
            let label = Fmt.day(DayKey.date(from: day) ?? now)
            guard !entries.isEmpty else { return CoachReply(text: "Für \(label) habe ich keine Ernährungseinträge gefunden.") }
            var body = "\(label):"
            for meal in MealType.allCases {
                let items = entries.filter { $0.meal == meal }
                guard !items.isEmpty else { continue }
                let kcal = items.reduce(0) { $0 + $1.nutrients.kcal }
                body += "\n\n\(meal.title) · \(Fmt.energyWithUnit(kcal, unit: context.prefs.energyUnit))"
                body += "\n" + items.map { "• \($0.name) (\($0.amountLabel))" }.joined(separator: "\n")
            }
            let total = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
            body += "\n\nGesamt: \(Fmt.energyWithUnit(total.kcal, unit: context.prefs.energyUnit)) · \(Fmt.number(total.protein)) g Protein"
            return CoachReply(text: body)
        }

        // „Wie viel Protein/Wasser habe ich heute …?“
        if text.containsAny(["wie viel", "wieviel"]), text.containsAny(["protein", "kalorien", "wasser", "getrunken", "gegessen", "eiweiss"]) {
            let day = text.day(now: now).key
            let label = Fmt.day(DayKey.date(from: day) ?? now)
            if text.containsAny(["wasser", "getrunken"]) {
                let ml = ((try? db.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.dayKey == day }))) ?? []).reduce(0) { $0 + $1.ml }
                let target = context.profile?.waterTargetMl ?? 0
                return CoachReply(text: "\(label): \(Fmt.volume(ml)) getrunken\(target > 0 ? " von \(Fmt.volume(Double(target)))" : "").")
            }
            let entries = (try? db.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.dayKey == day }))) ?? []
            let total = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
            let p = context.profile
            return CoachReply(text: """
            \(label): \(Fmt.energyWithUnit(total.kcal, unit: context.prefs.energyUnit))\(p.map { " von \(Fmt.energyWithUnit(Double($0.calorieTarget), unit: context.prefs.energyUnit))" } ?? "")
            Protein \(Fmt.number(total.protein)) g\(p.map { " / \($0.proteinTargetG) g" } ?? "") · Kohlenhydrate \(Fmt.number(total.carbs)) g · Fett \(Fmt.number(total.fat)) g
            """)
        }

        // „Wann habe ich zuletzt gewogen?“
        if text.contains("wann"), text.containsAny(["gewogen", "gewicht"]) {
            var d = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            d.fetchLimit = 1
            guard let entry = try? db.fetch(d).first else { return CoachReply(text: "Es gibt noch keinen Gewichtseintrag.") }
            return CoachReply(text: "Zuletzt am \(Fmt.mediumDate(entry.date)) um \(Fmt.time(entry.date)): \(Fmt.weightWithUnit(entry.kg, unit: context.prefs.weightUnit)).")
        }

        // „Wann habe ich zuletzt Kniebeugen gemacht?“
        if text.containsAny(["zuletzt", "letzte mal", "letztes mal"]), text.containsAny(["wann", "gemacht", "trainiert"]) {
            guard let exercise = matchExercise() else {
                return CoachReply(text: "Welche Übung meinst du? Ich habe in deiner Frage keine bekannte Übung gefunden.")
            }
            let exerciseID = exercise.id
            let logs = (try? db.fetch(FetchDescriptor<ExerciseLog>(predicate: #Predicate { $0.exerciseID == exerciseID }))) ?? []
            let performed = logs.compactMap { log -> (Date, ExerciseLog)? in
                guard let session = log.session else { return nil }
                return (session.startedAt, log)
            }.sorted { $0.0 > $1.0 }
            guard let latest = performed.first else {
                return CoachReply(text: "\(exercise.name) hast du noch nicht in einem Training erfasst.")
            }
            let best = latest.1.sortedSets.filter { $0.isCompleted && $0.kind != .warmup }.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }
            var body = "\(exercise.name) zuletzt am \(Fmt.mediumDate(latest.0))"
            if let name = latest.1.session?.name, !name.isEmpty { body += " („\(name)“)" }
            body += "."
            if let best {
                body += " Bester Satz: \(Fmt.weightWithUnit(best.weightKg, unit: context.prefs.weightUnit)) × \(best.reps)."
            }
            if let equipment = latest.1.equipmentLabel, !equipment.isEmpty {
                body += " Gerät: \(equipment)."
            }
            if let sessionID = latest.1.session?.id {
                var open = CoachAction(kind: .navigate, title: "Einheit ansehen")
                open.params[CoachParam.destination] = "workoutSession"
                open.params[CoachParam.sessionID] = sessionID.uuidString
                return CoachReply(text: body, actions: [open])
            }
            return CoachReply(text: body)
        }
        return nil
    }

    private func matchExercise() -> Exercise? {
        let all = (try? db.fetch(FetchDescriptor<Exercise>())) ?? []
        var best: (Exercise, Int)?
        for exercise in all {
            let name = CoachText.fold(exercise.name)
            var score = 0
            if text.folded.contains(name) {
                score = name.count * 2
            } else {
                for token in name.split(separator: " ") where token.count >= 5 {
                    let stem = token.count > 6 ? String(token.dropLast()) : String(token)
                    if text.folded.contains(stem) { score = max(score, stem.count) }
                }
            }
            if score > 0, score > (best?.1 ?? 0) { best = (exercise, score) }
        }
        return best?.0
    }

    // MARK: Gewicht

    private mutating func detectWeight() {
        guard !text.containsAny(["zielgewicht", "wunschgewicht", "wasserziel", "trinkziel"]) else { return }
        let weighWords = ["gewogen", "wiege", "gewicht", "waage", "wog ", "wägung"]
        let onlyNumber = text.matches(#"^\s*\d{2,3}([.,]\d{1,2})?\s*(kg|kilo)\s*\.?$"#)
        guard text.containsAny(weighWords) || onlyNumber else { return }

        var kg: Double?
        if let g = text.groups(#"(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:kg|kilo)"#) {
            kg = CoachParam.double(g[0])
        } else if let g = text.groups(#"(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:lb|lbs|pfund)"#), let lb = CoachParam.double(g[0]) {
            kg = WeightUnit.lb.toKg(lb)
        }
        guard let kg else {
            if text.containsAny(["gewogen", "wiege"]) {
                lines.append("Wie viel hast du gewogen? Bitte nenne den Wert, z. B. „82,4 kg“.")
            }
            return
        }
        let day = text.day(now: now)
        let time = text.time
        var action = CoachAction(kind: .logWeight, title: "Gewicht erfassen",
                                 detail: "\(Fmt.weightWithUnit(kg, unit: context.prefs.weightUnit, digits: 2)) · \(CoachParam.dayDescription(day.key, time: time))")
        action.params[CoachParam.kg] = CoachParam.string(kg)
        action.params[CoachParam.day] = day.key
        if let time { action.params[CoachParam.time] = time }
        actions.append(action)
    }

    // MARK: Wasser

    private mutating func detectWaterTarget() {
        guard text.containsAny(["wasserziel", "trinkziel"]) else { return }
        guard let ml = text.volumeMl(), text.containsAny(["auf ", "setz", "änder", "stell", "erhöh", "reduzier"]) else { return }
        var action = CoachAction(kind: .setWaterTarget, title: "Trinkziel ändern",
                                 detail: "Neues Tagesziel: \(Fmt.volume(ml))\(context.profile.map { " (bisher \(Fmt.volume(Double($0.waterTargetMl))))" } ?? "")")
        action.params[CoachParam.ml] = CoachParam.string(ml)
        actions.append(action)
    }

    private mutating func detectWater() {
        guard !text.containsAny(["wasserziel", "trinkziel"]) else { return }
        guard !actions.contains(where: { $0.kind == .logWater || $0.kind == .setWaterTarget }) else { return }
        let drinkWords = ["getrunken", "trinke", "trank", "wasser"]
        guard text.containsAny(drinkWords) else { return }
        // Wurde die Menge bereits einem Getränk mit Nährwerten zugeordnet?
        if actions.contains(where: { $0.kind == .logFood }) && !text.contains("wasser") { return }

        let beverage: String = text.contains("tee") ? "Tee" : "Wasser"
        let day = text.day(now: now)
        let time = text.time

        if let ml = text.volumeMl() {
            var action = CoachAction(kind: .logWater, title: "\(beverage) erfassen",
                                     detail: "\(Fmt.volume(ml)) · \(CoachParam.dayDescription(day.key, time: time))")
            action.params[CoachParam.ml] = CoachParam.string(ml)
            action.params[CoachParam.beverage] = beverage
            action.params[CoachParam.day] = day.key
            if let time { action.params[CoachParam.time] = time }
            actions.append(action)
            return
        }

        // Behälter ohne Mengenangabe → Menge erfragen, nicht schätzen.
        let containers: [(pattern: String, name: String, sizes: [Double])] = [
            ("gl[aä]s(?:er)?", "Glas", [200, 250, 300]),
            ("flaschen?", "Flasche", [330, 500, 750, 1000]),
            ("tassen?", "Tasse", [150, 200, 250]),
            ("becher", "Becher", [200, 300, 400])
        ]
        for container in containers {
            if let g = text.groups(#"(\d+|ein|eine|einen|zwei|drei|vier|fünf|sechs)?\s*"# + container.pattern + #"\b"#) {
                let count = CoachText.count(from: g.first ?? nil) ?? 1
                let choices = container.sizes.map { size -> CoachChoice in
                    let total = size * count
                    let label = count == 1 ? Fmt.volume(size) : "\(Fmt.decimal(count)) × \(Fmt.volume(size)) = \(Fmt.volume(total))"
                    return CoachChoice(label: label, params: [CoachParam.ml: CoachParam.string(total)])
                }
                var action = CoachAction(kind: .logWater, title: "\(beverage) erfassen",
                                         detail: "Wie gross war \(count == 1 ? "das \(container.name)" : "ein \(container.name)")?",
                                         status: .needsInput, choices: choices)
                action.params[CoachParam.beverage] = beverage
                action.params[CoachParam.day] = day.key
                action.params[CoachParam.needs] = CoachParam.ml
                if let time { action.params[CoachParam.time] = time }
                actions.append(action)
                return
            }
        }

        if text.containsAny(["getrunken", "trinke", "trank"]) {
            let choices = [250.0, 500, 750, 1000].map { CoachChoice(label: Fmt.volume($0), params: [CoachParam.ml: CoachParam.string($0)]) }
            var action = CoachAction(kind: .logWater, title: "\(beverage) erfassen", detail: "Welche Menge hast du getrunken?",
                                     status: .needsInput, choices: choices)
            action.params[CoachParam.beverage] = beverage
            action.params[CoachParam.day] = day.key
            action.params[CoachParam.needs] = CoachParam.ml
            actions.append(action)
        }
    }

    // MARK: Ernährung

    private static let mealWords: [(words: [String], meal: MealType)] = [
        (["frühstück", "fruhstuck", "zmorge", "morgenessen", "gefrühstückt"], .breakfast),
        (["mittagessen", "zmittag", "zu mittag", "mittags", "lunch"], .lunch),
        (["abendessen", "znacht", "zu abend", "abends", "dinner"], .dinner),
        (["snack", "zwischendurch", "zvieri", "znüni"], .snack)
    ]

    private static let foodStopWords: Set<String> = [
        "zum", "zu", "zur", "als", "beim", "am", "im", "gegessen", "getrunken", "und", "mit", "heute", "gestern",
        "vorgestern", "hatte", "habe", "gehabt", "zmorge", "zmittag", "znacht", "frühstück", "mittagessen", "abendessen",
        "snack", "morgens", "mittags", "abends", "danach", "dann", "noch", "auch", "ich", "um"
    ]

    private static let containerWords: Set<String> = ["portion", "portionen", "schale", "schalen", "teller", "stück", "scheibe",
                                                       "scheiben", "becher", "glas", "gläser", "tasse", "tassen", "handvoll", "löffel"]

    private var detectedMeal: MealType {
        for entry in Self.mealWords where text.containsAny(entry.words) { return entry.meal }
        return MealType.suggested(for: now)
    }

    private mutating func detectFood() {
        let eatWords = ["gegessen", "esse ", "ass ", "frühstück", "zmorge", "mittag", "abend", "znacht", "snack",
                        "zwischendurch", "hatte", "gefrühstückt", "zvieri", "znüni"]
        guard text.containsAny(eatWords) else { return }
        let day = text.day(now: now)
        let meal = detectedMeal

        // Mengenangabe in g/ml: „200 g Skyr“
        let gramMatches = text.allGroups(#"(\d+(?:[.,]\d+)?)\s*(g|gramm|ml)\s+([a-zäöüéèàç][\wäöüéèàç\-]*(?:\s+[a-zäöüéèàç][\wäöüéèàç\-]*){0,3})"#)
        for g in gramMatches {
            guard let grams = CoachParam.double(g.first ?? nil), let phrase = g.count > 2 ? g[2] : nil else { continue }
            let name = foodName(from: phrase)
            guard !name.isEmpty, name != "wasser" else { continue }
            proposeFood(term: name, grams: grams, servingCount: nil, servingHint: nil, meal: meal, day: day.key)
        }

        // Stückangabe: „2 Bananen“, „eine Portion Teigwaren“
        if gramMatches.isEmpty {
            let countMatches = text.allGroups(#"\b(\d{1,2}|ein|eine|einen|einem|zwei|drei|vier|fünf|sechs|halbe|halben)\s+([a-zäöüéèàç][\wäöüéèàç\-]*)(?:\s+([a-zäöüéèàç][\wäöüéèàç\-]*))?"#)
            for g in countMatches {
                guard let count = CoachText.count(from: g.first ?? nil), var word = g.count > 1 ? g[1] : nil else { continue }
                var hint: String?
                if Self.containerWords.contains(word), let next = g.count > 2 ? g[2] : nil {
                    hint = word
                    word = next
                }
                guard !Self.foodStopWords.contains(word), word.count >= 3, !["wasser", "kg", "kilo", "liter"].contains(word) else { continue }
                proposeFood(term: word, grams: nil, servingCount: count, servingHint: hint, meal: meal, day: day.key)
            }
        }
    }

    private func foodName(from phrase: String) -> String {
        var words: [String] = []
        for word in phrase.split(separator: " ").map(String.init) {
            if Self.foodStopWords.contains(word) { break }
            words.append(word)
        }
        return words.joined(separator: " ")
    }

    private mutating func proposeFood(term: String, grams: Double?, servingCount: Double?, servingHint: String?, meal: MealType, day: String) {
        guard let food = findFood(term) else {
            lines.append("„\(CoachText.capitalizedFirst(term))“ habe ich in deiner Lebensmitteldatenbank nicht gefunden.")
            var search = CoachAction(kind: .navigate, title: "In der Lebensmittelsuche öffnen", detail: meal.title)
            search.params[CoachParam.destination] = "foodSearch.\(meal.rawValue)"
            actions.append(search)
            return
        }
        var action = CoachAction(kind: .logFood, title: "\(food.name) erfassen", detail: "")
        action.params[CoachParam.foodID] = food.id.uuidString
        action.params[CoachParam.name] = food.name
        action.params[CoachParam.meal] = meal.rawValue
        action.params[CoachParam.day] = day

        var resolvedGrams = grams
        if resolvedGrams == nil, let count = servingCount {
            let servings = food.servings
            let serving = servings.first { s in servingHint.map { s.label.lowercased().contains($0.prefix(4)) } ?? false } ?? servings.first
            if let serving { resolvedGrams = serving.grams * count }
        }

        if let resolvedGrams {
            action.params[CoachParam.grams] = CoachParam.string(resolvedGrams)
            let kcal = food.per100.forGrams(resolvedGrams).kcal
            action.detail = "\(Fmt.decimal(resolvedGrams)) \(food.unitSymbol) · \(meal.title) · \(Fmt.energyWithUnit(kcal, unit: context.prefs.energyUnit))"
        } else {
            action.status = .needsInput
            action.params[CoachParam.needs] = CoachParam.grams
            action.detail = "Welche Menge? · \(meal.title)"
            let options: [Double] = food.servings.isEmpty ? [50, 100, 150, 200] : food.servings.prefix(3).map(\.grams)
            action.choices = options.map { grams in
                let total = grams * (servingCount ?? 1)
                return CoachChoice(label: "\(Fmt.decimal(total)) \(food.unitSymbol)", params: [CoachParam.grams: CoachParam.string(total)])
            }
        }
        actions.append(action)
    }

    /// Sucht im lokalen Katalog: exakte Treffer zuerst, dann häufig genutzte, dann kurze Namen.
    private func findFood(_ term: String) -> FoodItem? {
        let folded = CoachText.fold(term).trimmingCharacters(in: .whitespaces)
        guard folded.count >= 2 else { return nil }
        var candidates = [folded]
        for suffix in ["en", "n", "s", "e"] where folded.hasSuffix(suffix) && folded.count > suffix.count + 2 {
            candidates.append(String(folded.dropLast(suffix.count)))
        }
        for candidate in candidates {
            let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.searchKey.contains(candidate) && $0.isHidden == false })
            let results = (try? db.fetch(descriptor)) ?? []
            guard !results.isEmpty else { continue }
            return results.min { a, b in
                let an = CoachText.fold(a.name), bn = CoachText.fold(b.name)
                let ae = an == candidate || an == folded, be = bn == candidate || bn == folded
                if ae != be { return ae }
                let ap = an.hasPrefix(candidate), bp = bn.hasPrefix(candidate)
                if ap != bp { return ap }
                if a.useCount != b.useCount { return a.useCount > b.useCount }
                return a.name.count < b.name.count
            }
        }
        return nil
    }

    // MARK: Supplements

    private mutating func detectSupplements() {
        guard text.containsAny(["genommen", "eingenommen", "nehme", "geschluckt"]) else { return }
        let supplements = (try? db.fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.isActive == true }))) ?? []
        let day = text.day(now: now)
        let time = text.time
        var matched = 0
        for supplement in supplements {
            let name = CoachText.fold(supplement.name)
            let firstWord = name.split(separator: " ").first.map(String.init) ?? name
            guard text.folded.contains(name) || (firstWord.count >= 4 && text.folded.contains(firstWord)) else { continue }
            var action = CoachAction(kind: .logSupplement, title: "\(supplement.name) eingenommen",
                                     detail: "\(Fmt.decimal(supplement.servingsPerIntake)) × \(supplement.servingLabel) · \(CoachParam.dayDescription(day.key, time: time))")
            action.params[CoachParam.supplementID] = supplement.id.uuidString
            action.params[CoachParam.day] = day.key
            if let time { action.params[CoachParam.time] = time }
            actions.append(action)
            matched += 1
        }
        if matched == 0, !text.containsAny(["kg", "gewogen"]) {
            if supplements.isEmpty {
                lines.append("Du hast noch keine Supplements angelegt. Lege sie zuerst im Bereich Supplements an.")
                var open = CoachAction(kind: .navigate, title: "Supplements öffnen")
                open.params[CoachParam.destination] = "supplements"
                actions.append(open)
            } else {
                lines.append("Welches Supplement meinst du? Aktiv sind: \(supplements.map(\.name).joined(separator: ", ")).")
                quickReplies.append(contentsOf: supplements.prefix(3).map { "\($0.name) genommen" })
            }
        }
    }

    // MARK: Trainingsnotiz & Belastung

    private static let trainingWords = ["training", "workout", "einheit", "gym", "beintag", "leg day", "session", "trainiert", "studio"]
    private static let feelingWords = ["anstrengend", "hart", "schwer", "erschöpft", "erschopft", "kaputt", "platt", "fertig", "müde",
                                       "locker", "leicht", "easy", "lief gut", "gut gelaufen", "super", "schlecht", "zäh", "muskelkater", "notiz"]
    private static let bodyGroups: [(label: String, keys: [String])] = [
        ("Bein", ["bein", "leg", "unterkörper", "unterkorper", "lower", "squat"]),
        ("Oberkörper", ["oberkörper", "oberkorper", "upper"]),
        ("Push", ["push", "drück", "druck"]),
        ("Pull", ["pull", "zieh"]),
        ("Brust", ["brust", "chest"]),
        ("Rücken", ["rücken", "rucken", "back"]),
        ("Schulter", ["schulter", "shoulder"]),
        ("Arme", ["arm", "bizeps", "trizeps"]),
        ("Ganzkörper", ["ganzkörper", "ganzkorper", "full body", "fullbody"])
    ]

    private mutating func detectWorkoutNote() {
        guard text.containsAny(Self.trainingWords), text.containsAny(Self.feelingWords) else { return }

        let weighWords = ["gewogen", "wiege", "waage", "wägung"]
        let noteClauses = text.clauses.filter { clause in
            let c = clause.lowercased()
            let relevant = Self.trainingWords.contains { c.contains($0) } || Self.feelingWords.contains { c.contains($0) }
            return relevant && !weighWords.contains { c.contains($0) }
        }
        guard !noteClauses.isEmpty else { return }
        let note = CoachText.capitalizedFirst(noteClauses.joined(separator: ", ")) + "."

        let day = text.day(now: now)
        guard let dayStart = DayKey.date(from: day.key) else { return }
        let dayEnd = dayStart.adding(days: 1)
        let daySessions = (try? db.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= dayStart && $0.startedAt < dayEnd },
            sortBy: [SortDescriptor(\.startedAt)]))) ?? []

        let groups = Self.bodyGroups.filter { text.containsAny($0.keys) }
        let matching: [WorkoutSession] = groups.isEmpty ? daySessions : daySessions.filter { session in
            let name = session.name.lowercased()
            return groups.contains { group in group.keys.contains { name.contains($0) } }
        }

        var choices: [CoachChoice] = []
        var sessionID: String?
        if matching.count == 1 {
            sessionID = matching[0].id.uuidString
        } else {
            var options = matching.count > 1 ? matching : daySessions
            if options.isEmpty {
                var d = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
                d.fetchLimit = 3
                options = (try? db.fetch(d)) ?? []
            }
            guard !options.isEmpty else {
                lines.append("Ich habe noch keine Trainingseinheit gefunden, der ich die Notiz „\(note)“ zuordnen kann. Erfasse das Training im Bereich Training – danach kann ich die Notiz ergänzen.")
                return
            }
            choices = options.map { session in
                let when = Calendar.current.isDate(session.startedAt, inSameDayAs: dayStart)
                    ? Fmt.time(session.startedAt) : Fmt.shortDate(session.startedAt)
                return CoachChoice(label: "\(session.name.isEmpty ? "Training" : session.name) · \(when)",
                                   params: [CoachParam.sessionID: session.id.uuidString])
            }
            choices.append(CoachChoice(label: "Nicht speichern", params: [:], rejects: true))
            let groupText = groups.first.map { "\($0.label)training" } ?? "Training"
            lines.append(daySessions.isEmpty
                ? "Für \(Fmt.day(dayStart)) habe ich kein \(groupText) gefunden. Zu welcher Einheit gehört die Notiz?"
                : "Zu welcher Einheit gehört die Notiz?")
        }

        let sessionLabel = sessionID != nil ? matching[0].name : "Einheit wählen"
        var noteAction = CoachAction(kind: .addWorkoutNote, title: "Trainingsnotiz", detail: "„\(note)“ · \(sessionLabel)",
                                     status: sessionID == nil ? .needsInput : .proposed, choices: choices)
        noteAction.params[CoachParam.note] = note
        if let sessionID { noteAction.params[CoachParam.sessionID] = sessionID } else { noteAction.params[CoachParam.needs] = CoachParam.sessionID }
        actions.append(noteAction)

        if let derived = derivedExertion() {
            let (value, phrase) = derived
            var exertion = CoachAction(kind: .setSessionExertion, title: "Subjektive Belastung",
                                       detail: "\(value)/10 · abgeleitet aus „\(phrase)“ – bitte prüfen",
                                       status: sessionID == nil ? .needsInput : .proposed, isDerived: true)
            exertion.params[CoachParam.exertion] = String(value)
            if let sessionID { exertion.params[CoachParam.sessionID] = sessionID } else { exertion.params[CoachParam.needs] = CoachParam.sessionID }
            actions.append(exertion)
        }
    }

    /// Leitet eine Session-RPE aus der Formulierung ab. Wird als abgeleitet markiert.
    private func derivedExertion() -> (Int, String)? {
        let intensifiers = ["richtig", "sehr", "total", "extrem", "mega", "brutal", "völlig", "komplett", "unglaublich"]
        let hard = ["anstrengend", "hart", "schwer", "erschöpft", "kaputt", "platt", "fertig", "zäh"]
        let easy = ["locker", "leicht", "easy", "entspannt"]
        let medium = ["okay", "ok", "mittel", "normal"]
        if let word = hard.first(where: { text.contains($0) }) {
            let strong = intensifiers.first { text.contains("\($0) \(word)") } ?? intensifiers.first { text.contains($0) }
            let phrase = strong.map { "\($0) \(word)" } ?? word
            return (strong != nil ? 9 : 8, phrase)
        }
        if let word = easy.first(where: { text.contains($0) }) { return (4, word) }
        if let word = medium.first(where: { text.contains($0) }) { return (6, word) }
        return nil
    }

    // MARK: Zielwechsel

    private mutating func detectGoalChange() {
        let intent = ["ich will", "ich möchte", "möchte jetzt", "will jetzt", "mein ziel", "ziel ändern", "ziel wechseln",
                      "neues ziel", "lieber", "umstellen auf", "wechseln zu"]
        guard text.containsAny(intent) else { return }
        let map: [(String, FitnessGoal)] = [
            ("rekomp", .recomposition), ("muskel", .buildMuscle), ("masse aufbauen", .buildMuscle),
            ("abnehm", .loseWeight), ("fett verlieren", .loseWeight), ("fett reduzieren", .loseWeight),
            ("zunehm", .gainWeight), ("gewicht halten", .maintain), ("halten", .maintain),
            ("fitter", .fitness), ("fitness", .fitness), ("kraft", .strengthEndurance), ("ausdauer", .strengthEndurance),
            ("gesünder", .healthierLife), ("gesunder leben", .healthierLife)
        ]
        guard let goal = map.first(where: { text.contains($0.0) })?.1 else { return }
        guard let profile = context.profile else { return }
        if profile.primaryGoal == goal {
            lines.append("\(goal.title) ist bereits dein Hauptziel.")
            return
        }
        var inputs = ProfileService.energyInputs(for: profile, in: db)
        inputs.goal = goal
        let preview = EnergyCalculator.compute(inputs, formula: profile.energyFormula, tdeeOverride: profile.adaptiveTDEE)
        let kcalText = profile.targetsAreManual
            ? "Deine manuell festgelegten Zielwerte bleiben bestehen."
            : "Neues Kalorienziel ca. \(Fmt.energyWithUnit(Double(preview.calorieTarget), unit: context.prefs.energyUnit)), Protein \(preview.proteinG) g."
        var action = CoachAction(kind: .changeGoal, title: "Ziel ändern: \(profile.primaryGoal.title) → \(goal.title)",
                                 detail: "\(kcalText) Bisherige Einträge und deine Trainingshistorie bleiben vollständig erhalten.")
        action.params[CoachParam.goal] = goal.rawValue
        actions.append(action)
        if goal.needsTargetWeight {
            quickReplies.append("Wo stelle ich mein Wunschgewicht ein?")
        }
    }

    // MARK: Training starten

    private mutating func detectStartWorkout() {
        guard text.containsAny(["starte training", "training starten", "workout starten", "starte das training",
                                "starte mein training", "training beginnen", "starte ein training"]) else { return }
        actions.append(CoachAction(kind: .startWorkout, title: "Training öffnen", detail: "Wähle dort deine Vorlage und starte die Einheit."))
    }

    // MARK: Navigation

    static let navigationVerbs = ["öffne", "zeig", "geh zu", "gehe zu", "bring mich", "wo finde", "wo kann ich", "wo stelle",
                                  "wo ändere", "navigier", "wechsle zu", "wo sehe", "wo ist"]

    private static let destinationKeywords: [(String, String)] = [
        ("einstellung", "settings"), ("supplement", "supplements"), ("zyklus", "cycle"), ("gewohnheit", "habits"),
        ("rezept", "recipes"), ("gespeicherte mahlzeit", "savedMeals"), ("körpermass", "measurements"), ("umfang", "measurements"),
        ("umfänge", "measurements"), ("3d", "bodyAvatar"), ("avatar", "bodyAvatar"), ("fortschrittsfoto", "progressPhotos"),
        ("foto", "progressPhotos"), ("wochenanalyse", "weeklyReport"), ("wochenbericht", "weeklyReport"),
        ("energiebedarf", "energyInsight"), ("übungsbibliothek", "exerciseLibrary"), ("übungen", "exerciseLibrary"),
        ("trainingshistorie", "workoutHistory"), ("trainingsverlauf", "workoutHistory"), ("studio", "gymProfiles"),
        ("plan erstellen", "planGenerator"), ("trainingsplan", "planGenerator"), ("protokoll", "auditLog"),
        ("gewicht", "weight"), ("wasser", "water"), ("ernährung", "tab.nutrition"), ("tagebuch", "tab.nutrition"),
        ("training", "tab.training"), ("fortschritt", "tab.progress"), ("startseite", "tab.today"), ("dashboard", "tab.today")
    ]

    private mutating func detectNavigation() {
        let isSettingsQuestion = text.containsAny(["einstell", "wo stelle", "wo ändere", "wo kann ich", "anpassen", "ändern"])
        guard text.containsAny(Self.navigationVerbs) || isSettingsQuestion else { return }

        // Sonderfälle
        let specials: [([String], SettingsSection)] = [
            (["wasserziel", "trinkziel", "kalorienziel", "makroziel", "proteinziel", "schrittziel"], .targets),
            (["wunschgewicht", "zielgewicht"], .goals)
        ]
        for (words, section) in specials where text.containsAny(words) {
            appendSettings(section)
            return
        }

        if isSettingsQuestion {
            var best: (SettingsSection, Int)?
            for section in SettingsSection.allCases {
                let score = section.keywords.filter { text.contains($0) }.map(\.count).reduce(0, +)
                if score > 0, score > (best?.1 ?? 0) { best = (section, score) }
            }
            if let best {
                appendSettings(best.0)
                return
            }
        }

        if let match = Self.destinationKeywords.first(where: { text.contains($0.0) }) {
            let key = match.1
            if key == "cycle" && !context.prefs.isEnabled(.cycle) {
                lines.append("Das Zyklusmodul ist deaktiviert. Du kannst es unter Module einschalten.")
                appendSettings(.modules)
                return
            }
            var action = CoachAction(kind: .navigate, title: "\(CoachDestinations.title(for: key)) öffnen")
            action.params[CoachParam.destination] = key
            actions.append(action)
        }
    }

    private mutating func appendSettings(_ section: SettingsSection) {
        var action = CoachAction(kind: .openSettings, title: "\(section.title) öffnen", detail: "Einstellungen")
        action.params[CoachParam.section] = section.rawValue
        actions.append(action)
    }

    // MARK: Bilder

    private mutating func handleImage(_ analysis: CoachImageAnalysis) {
        let day = DayKey.make(now)
        switch analysis.kind {
        case .nutritionLabel:
            guard let kcal = analysis.kcalPer100 else {
                lines.append("Ich habe ein Nährwertetikett erkannt, konnte die Werte aber nicht sicher lesen. Scanne am besten den Barcode.")
                var scan = CoachAction(kind: .navigate, title: "Lebensmittelsuche öffnen")
                scan.params[CoachParam.destination] = "foodSearch.\(detectedMeal.rawValue)"
                actions.append(scan)
                return
            }
            let name = analysis.productName ?? "Produkt vom Etikett"
            var parts = ["\(Fmt.number(kcal)) kcal"]
            if let p = analysis.proteinPer100 { parts.append("\(Fmt.decimal(p)) g Protein") }
            if let c = analysis.carbsPer100 { parts.append("\(Fmt.decimal(c)) g KH") }
            if let f = analysis.fatPer100 { parts.append("\(Fmt.decimal(f)) g Fett") }
            lines.append("Vom Etikett gelesen (pro 100 g/ml): \(parts.joined(separator: " · ")). Die Texterkennung kann Fehler machen – bitte prüfe die Werte.")
            var action = CoachAction(kind: .logFood, title: "\(name) erfassen", detail: "Welche Menge? · KI-erkannt, unbestätigt",
                                     status: .needsInput, isDerived: true)
            action.params[CoachParam.name] = name
            action.params[CoachParam.kcal100] = CoachParam.string(kcal)
            if let p = analysis.proteinPer100 { action.params[CoachParam.protein100] = CoachParam.string(p) }
            if let c = analysis.carbsPer100 { action.params[CoachParam.carbs100] = CoachParam.string(c) }
            if let f = analysis.fatPer100 { action.params[CoachParam.fat100] = CoachParam.string(f) }
            action.params[CoachParam.meal] = detectedMeal.rawValue
            action.params[CoachParam.day] = day
            action.params[CoachParam.needs] = CoachParam.grams
            action.params[CoachParam.quality] = DataQuality.aiUnconfirmed.rawValue
            action.choices = [30.0, 50, 100, 150, 250].map { CoachChoice(label: "\(Fmt.decimal($0)) g", params: [CoachParam.grams: CoachParam.string($0)]) }
            actions.append(action)

        case .supplementLabel:
            lines.append("Das sieht nach einem Supplement-Etikett aus\(analysis.productName.map { " („\($0)“)" } ?? ""). Du kannst es im Bereich Supplements anlegen – Kern übernimmt nur deine eigenen Angaben zur Einnahme, keine Dosierungsempfehlungen.")
            var open = CoachAction(kind: .navigate, title: "Supplements öffnen")
            open.params[CoachParam.destination] = "supplements"
            actions.append(open)

        case .food:
            var proposed = false
            for term in analysis.foodSearchTerms.prefix(2) {
                guard let food = findFood(term) else { continue }
                var action = CoachAction(kind: .logFood, title: "\(food.name) erfassen",
                                         detail: "Auf dem Foto erkannt · KI-Schätzung, unbestätigt · Welche Menge?",
                                         status: .needsInput, isDerived: true)
                action.params[CoachParam.foodID] = food.id.uuidString
                action.params[CoachParam.name] = food.name
                action.params[CoachParam.meal] = detectedMeal.rawValue
                action.params[CoachParam.day] = day
                action.params[CoachParam.needs] = CoachParam.grams
                let options: [Double] = food.servings.isEmpty ? [80, 150, 250, 350] : food.servings.prefix(3).map(\.grams)
                action.choices = options.map { CoachChoice(label: "\(Fmt.decimal($0)) \(food.unitSymbol)", params: [CoachParam.grams: CoachParam.string($0)]) }
                actions.append(action)
                proposed = true
            }
            lines.append(proposed
                ? "Auf dem Bild glaube ich Folgendes zu erkennen. Die Erkennung ist eine Schätzung – Portionsgrössen kann ich nicht messen. Bitte wähle die Menge und prüfe den Eintrag."
                : "Ich habe Essen erkannt, aber nichts Passendes in deiner Datenbank gefunden. Suche es am besten manuell.")
            if !proposed {
                var search = CoachAction(kind: .navigate, title: "Lebensmittelsuche öffnen")
                search.params[CoachParam.destination] = "foodSearch.\(detectedMeal.rawValue)"
                actions.append(search)
            }

        case .unknown:
            if !analysis.text.isEmpty && text.isEmpty {
                lines.append("Ich habe Text auf dem Bild erkannt, aber kein Etikett oder Lebensmittel. Was soll ich damit tun?")
            } else if text.isEmpty {
                lines.append("Auf dem Bild konnte ich nichts Eindeutiges erkennen. Beschreibe mir kurz, was ich erfassen soll.")
            }
        }
    }
}
