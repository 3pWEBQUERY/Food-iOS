import AppIntents
import Foundation

/// Öffnet einen Bereich der App über einen Deep Link (`kern://…`).
private func widgetDeepLink(_ path: String) -> URL {
    URL(string: "kern://\(path)") ?? URL(string: "kern://today")!
}

struct WidgetLogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Mahlzeit erfassen"
    static let description = IntentDescription("Öffnet die Lebensmittelsuche in Kern.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(widgetDeepLink("log/food")))
    }
}

struct WidgetLogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewicht erfassen"
    static let description = IntentDescription("Öffnet die Gewichtserfassung in Kern.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(widgetDeepLink("log/weight")))
    }
}

struct WidgetAskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Coach fragen"
    static let description = IntentDescription("Öffnet den KI-Coach in Kern.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(widgetDeepLink("coach")))
    }
}

struct WidgetScanBarcodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Barcode scannen"
    static let description = IntentDescription("Öffnet den Barcode-Scanner in Kern.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(widgetDeepLink("log/barcode")))
    }
}

/// Siri- und Kurzbefehle-Integration.
struct KernAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WidgetLogMealIntent(),
            phrases: ["Mahlzeit in \(.applicationName) erfassen", "Essen in \(.applicationName) eintragen"],
            shortTitle: "Mahlzeit erfassen",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: AddWaterIntent(),
            phrases: ["Wasser in \(.applicationName) erfassen", "Ein Glas Wasser in \(.applicationName)"],
            shortTitle: "Wasser erfassen",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: WidgetLogWeightIntent(),
            phrases: ["Gewicht in \(.applicationName) erfassen"],
            shortTitle: "Gewicht erfassen",
            systemImageName: "scalemass"
        )
        AppShortcut(
            intent: WidgetAskCoachIntent(),
            phrases: ["\(.applicationName) Coach fragen", "Coach in \(.applicationName) öffnen"],
            shortTitle: "Coach fragen",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: WidgetScanBarcodeIntent(),
            phrases: ["Barcode in \(.applicationName) scannen"],
            shortTitle: "Barcode scannen",
            systemImageName: "barcode.viewfinder"
        )
    }
}
