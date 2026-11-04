import Foundation
import SwiftData

/// Eingabe an den Coach.
struct CoachInput {
    var text: String
    var imageData: Data?
    /// Ergebnis der lokalen Bildanalyse (falls ein Bild angehängt wurde).
    var imageAnalysis: CoachImageAnalysis?
}

/// Antwort des Coaches: Text, strukturierte Aktionen und Antwortvorschläge.
struct CoachReply {
    var text: String
    var actions: [CoachAction] = []
    var quickReplies: [String] = []
}

/// Kontext für die Verarbeitung (nur lokal verfügbar, wird nicht vollständig übertragen).
@MainActor
struct CoachContext {
    let modelContext: ModelContext
    let profile: UserProfile?
    let prefs: AppPreferences
    let now: Date
}

/// Austauschbare Coach-Implementierung (lokal regelbasiert oder serverseitige KI).
protocol CoachEngine {
    @MainActor
    func respond(to input: CoachInput, context: CoachContext) async throws -> CoachReply
}

enum CoachEngineError: LocalizedError {
    case invalidBackend
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBackend: "Kein gültiges Backend konfiguriert."
        case .badResponse(let code): "Der Server hat mit Status \(code) geantwortet."
        }
    }
}

/// Serverseitige KI über das Kern-Backend. Wird nur mit ausdrücklicher Zustimmung genutzt.
/// Übertragen werden ausschliesslich die Nachricht, ein optionales Bild und ein minimaler Kontext.
struct RemoteCoachEngine: CoachEngine {
    let baseURL: String

    private struct RequestBody: Encodable {
        struct Context: Encodable {
            var date: String
            var locale: String
            var primaryGoal: String?
            var weightUnit: String
            var energyUnit: String
        }
        var text: String
        var image: String?
        var context: Context
    }

    private struct ResponseBody: Decodable {
        struct Action: Decodable {
            var kind: String
            var params: [String: String]?
            var title: String?
            var detail: String?
        }
        var text: String
        var actions: [Action]?
        var quickReplies: [String]?
    }

    @MainActor
    func respond(to input: CoachInput, context: CoachContext) async throws -> CoachReply {
        guard var url = URL(string: baseURL), url.host != nil else { throw CoachEngineError.invalidBackend }
        url.append(path: "v1/coach/messages")

        let body = RequestBody(
            text: input.text,
            image: input.imageData?.base64EncodedString(),
            context: .init(date: DayKey.make(context.now), locale: "de-CH",
                           primaryGoal: context.profile?.primaryGoalRaw,
                           weightUnit: context.prefs.weightUnit.rawValue,
                           energyUnit: context.prefs.energyUnit.rawValue)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainStore.get(KeychainStore.Keys.backendSession) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CoachEngineError.badResponse(status) }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)

        let actions: [CoachAction] = (decoded.actions ?? []).compactMap { remote in
            guard let kind = CoachAction.Kind(rawValue: remote.kind) else { return nil }
            var action = CoachAction(kind: kind, title: remote.title ?? kind.rawValue,
                                     detail: remote.detail ?? "", params: remote.params ?? [:])
            action.isDestructive = kind == .deleteEntry || kind == .deleteLastWeight
            return action
        }
        return CoachReply(text: decoded.text, actions: actions, quickReplies: decoded.quickReplies ?? [])
    }
}
