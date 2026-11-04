import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var dayKey: String = ""
    var kg: Double = 0
    var sourceRaw: String = EntrySource.manual.rawValue
    var note: String = ""
    /// UUID des Health-Samples zur zuverlässigen Duplikaterkennung.
    var healthKitUUID: String? = nil

    init(kg: Double, date: Date = .now, source: EntrySource = .manual, note: String = "") {
        self.kg = kg
        self.date = date
        self.dayKey = DayKey.make(date)
        self.sourceRaw = source.rawValue
        self.note = note
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
}

/// Körpermasse. Alle Werte optional – nur tatsächlich gemessene Werte werden gespeichert.
@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date()
    var neckCm: Double? = nil
    var shoulderCm: Double? = nil
    var chestCm: Double? = nil
    var waistCm: Double? = nil
    var hipCm: Double? = nil
    var armCm: Double? = nil
    var thighCm: Double? = nil
    var calfCm: Double? = nil
    var bodyFatPercent: Double? = nil
    var note: String = ""

    init(date: Date = .now) {
        self.date = date
    }

    /// Alle Messpunkte für generische Darstellung.
    static let fields: [(key: String, title: String)] = [
        ("neckCm", "Hals"), ("shoulderCm", "Schultern"), ("chestCm", "Brust"),
        ("waistCm", "Taille"), ("hipCm", "Hüfte"), ("armCm", "Oberarm"),
        ("thighCm", "Oberschenkel"), ("calfCm", "Wade")
    ]

    func value(for key: String) -> Double? {
        switch key {
        case "neckCm": neckCm
        case "shoulderCm": shoulderCm
        case "chestCm": chestCm
        case "waistCm": waistCm
        case "hipCm": hipCm
        case "armCm": armCm
        case "thighCm": thighCm
        case "calfCm": calfCm
        case "bodyFatPercent": bodyFatPercent
        default: nil
        }
    }

    func setValue(_ value: Double?, for key: String) {
        switch key {
        case "neckCm": neckCm = value
        case "shoulderCm": shoulderCm = value
        case "chestCm": chestCm = value
        case "waistCm": waistCm = value
        case "hipCm": hipCm = value
        case "armCm": armCm = value
        case "thighCm": thighCm = value
        case "calfCm": calfCm = value
        case "bodyFatPercent": bodyFatPercent = value
        default: break
        }
    }
}

enum PhotoPose: String, Codable, CaseIterable, Identifiable {
    case front, side, back
    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: "Vorne"
        case .side: "Seite"
        case .back: "Hinten"
        }
    }
}

/// Privates Fortschrittsfoto – verbleibt lokal, wird nie geteilt ohne ausdrückliche Aktion.
@Model
final class ProgressPhoto {
    var id: UUID = UUID()
    var date: Date = Date()
    var poseRaw: String = PhotoPose.front.rawValue
    @Attribute(.externalStorage) var imageData: Data = Data()
    var note: String = ""

    init(imageData: Data, pose: PhotoPose, date: Date = .now) {
        self.imageData = imageData
        self.poseRaw = pose.rawValue
        self.date = date
    }

    var pose: PhotoPose { PhotoPose(rawValue: poseRaw) ?? .front }
}

// MARK: - Zyklus

enum CycleFlow: String, Codable, CaseIterable, Identifiable {
    case none, spotting, light, medium, heavy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Keine"
        case .spotting: "Schmierblutung"
        case .light: "Leicht"
        case .medium: "Mittel"
        case .heavy: "Stark"
        }
    }
    var isBleeding: Bool { self == .light || self == .medium || self == .heavy }
}

enum CycleSymptom: String, Codable, CaseIterable, Identifiable {
    case cramps, headache, bloating, backPain, tenderBreasts, fatigue, cravings, acne, nausea, sleepIssues, moodSwings, lowMotivation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cramps: "Krämpfe"
        case .headache: "Kopfschmerzen"
        case .bloating: "Blähungen"
        case .backPain: "Rückenschmerzen"
        case .tenderBreasts: "Brustspannen"
        case .fatigue: "Müdigkeit"
        case .cravings: "Heisshunger"
        case .acne: "Hautunreinheiten"
        case .nausea: "Übelkeit"
        case .sleepIssues: "Schlafprobleme"
        case .moodSwings: "Stimmungsschwankungen"
        case .lowMotivation: "Wenig Antrieb"
        }
    }
}

/// Tageseintrag im Zyklusmodul. Besonders schützenswerte Daten.
@Model
final class CycleDay {
    var id: UUID = UUID()
    var dayKey: String = ""
    var date: Date = Date()
    var flowRaw: String = CycleFlow.none.rawValue
    var symptomsRaw: [String] = []
    /// 0 = keine Angabe, 1–5 Skala.
    var energy: Int = 0
    var mood: Int = 0
    var exertionCapacity: Int = 0
    var note: String = ""

    init(date: Date) {
        self.date = date.startOfDay
        self.dayKey = DayKey.make(date)
    }

    var flow: CycleFlow {
        get { CycleFlow(rawValue: flowRaw) ?? .none }
        set { flowRaw = newValue.rawValue }
    }

    var symptoms: [CycleSymptom] {
        get { symptomsRaw.compactMap(CycleSymptom.init(rawValue:)) }
        set { symptomsRaw = newValue.map(\.rawValue) }
    }
}
