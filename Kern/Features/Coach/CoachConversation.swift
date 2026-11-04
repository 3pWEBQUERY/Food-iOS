import Foundation
import Observation
import SwiftData

/// Steuert einen Coach-Durchlauf: Nachricht speichern, Engine wählen, Aktionen validieren,
/// freigegebene Automatisierungen anwenden und die Antwort persistieren.
@MainActor
@Observable
final class CoachConversation {
    var isThinking = false

    func send(text: String, image: Data?, context: ModelContext, prefs: AppPreferences,
              profile: UserProfile?, executor: ActionExecutor) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { return }

        let userMessage = CoachMessage(role: "user", text: trimmed)
        userMessage.imageData = image
        context.insert(userMessage)
        context.saveQuietly()

        isThinking = true
        defer { isThinking = false }

        let coachContext = CoachContext(modelContext: context, profile: profile, prefs: prefs, now: .now)
        var input = CoachInput(text: trimmed, imageData: image, imageAnalysis: nil)
        var reply: CoachReply
        var serverNote: String?

        let useRemote = prefs.hasBackend && prefs.aiProcessingConsent && !prefs.isGuestMode
        if useRemote {
            do {
                reply = try await RemoteCoachEngine(baseURL: prefs.backendBaseURL).respond(to: input, context: coachContext)
            } catch {
                serverNote = "Der Kern-Server war nicht erreichbar – ich habe deine Nachricht lokal verarbeitet."
                if let image { input.imageAnalysis = await CoachImageAnalyzer.analyze(image) }
                reply = (try? await LocalCoachEngine().respond(to: input, context: coachContext)) ?? CoachReply(text: "")
            }
        } else {
            if let image { input.imageAnalysis = await CoachImageAnalyzer.analyze(image) }
            reply = (try? await LocalCoachEngine().respond(to: input, context: coachContext)) ?? CoachReply(text: "")
        }

        // Validierung und freigegebene Automatisierungen
        var actions: [CoachAction] = []
        for var action in reply.actions {
            if action.status == .proposed, let error = ActionValidator.validate(action, prefs: prefs, context: context) {
                action.status = .failed
                action.resultNote = error
            } else if action.status == .proposed, !action.isDestructive,
                      let key = action.automationKey, prefs.coachAutomations.contains(key) {
                action = executor.apply(action)
                action.wasAutoApplied = action.status == .applied
            }
            actions.append(action)
        }

        var textParts: [String] = []
        if let serverNote { textParts.append(serverNote) }
        if !reply.text.isEmpty { textParts.append(reply.text) }
        if actions.contains(where: \.wasAutoApplied) {
            textParts.append("Gemäss deiner Automatisierungsregeln habe ich Einträge direkt übernommen. Du kannst sie jederzeit rückgängig machen.")
        }

        let assistant = CoachMessage(role: "assistant", text: textParts.joined(separator: "\n\n"))
        assistant.quickReplies = reply.quickReplies
        CoachActionStore.setActions(actions, on: assistant)
        context.insert(assistant)
        context.saveQuietly()
    }

    func clearHistory(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<CoachMessage>())) ?? []
        for message in all { context.delete(message) }
        context.saveQuietly()
    }
}
