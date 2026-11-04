import SwiftUI

/// Kurzes, interaktives Tutorial nach dem Onboarding. Jederzeit überspringbar,
/// erscheint danach nicht erneut automatisch (neu startbar in den Einstellungen).
struct TutorialOverlay: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router
    @State private var index = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let tint: Color
        let title: String
        let text: String
        let tab: AppTab
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "sun.max", tint: Theme.accent, title: "Heute",
             text: "Dein persönliches Dashboard. Über „Anpassen“ ordnest du Karten neu oder blendest sie aus.", tab: .today),
        Page(id: 1, symbol: "plus.circle", tint: Theme.accent, title: "Erfassen",
             text: "Der mittlere Tab öffnet die Schnellerfassung: Mahlzeit, Barcode, Wasser, Gewicht oder Training.", tab: .today),
        Page(id: 2, symbol: "bubble.left.and.text.bubble.right", tint: Theme.accent, title: "Dein Coach",
             text: "Schreib oder sprich ganz normal, z. B. „Heute 82,4 kg gewogen“. Der Coach bereitet Einträge vor – du bestätigst.", tab: .today),
        Page(id: 3, symbol: "dumbbell", tint: Theme.training, title: "Training",
             text: "Pläne, Gym-Tagebuch, Pausentimer und Rekorde. Funktioniert auch komplett offline.", tab: .training),
        Page(id: 4, symbol: "chart.line.uptrend.xyaxis", tint: Theme.weight, title: "Fortschritt",
             text: "Hier verbindet Kern Ernährung, Training und Gewicht – mit klarer Unterscheidung zwischen Beobachtung und Schätzung.", tab: .progress)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { advance() }
                .accessibilityHidden(true)

            let page = pages[index]
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack {
                    Image(systemName: page.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(page.tint)
                        .symbolEffect(.bounce, value: index)
                    Spacer()
                    Button("Überspringen") { finish() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.title).font(.title2.weight(.bold))
                    Text(page.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(index)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                HStack {
                    HStack(spacing: 6) {
                        ForEach(pages) { p in
                            Capsule()
                                .fill(p.id == index ? Theme.accent : Theme.fillStrong)
                                .frame(width: p.id == index ? 18 : 6, height: 6)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Schritt \(index + 1) von \(pages.count)")
                    Spacer()
                    Button(index == pages.count - 1 ? "Fertig" : "Weiter") { advance() }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(Theme.Space.l)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 120)
        }
        .animation(.smooth(duration: 0.35), value: index)
    }

    private func advance() {
        if index < pages.count - 1 {
            index += 1
            router.selectedTab = pages[index].tab
        } else {
            finish()
        }
    }

    private func finish() {
        router.selectedTab = .today
        withAnimation(.smooth) { prefs.hasSeenTutorial = true }
    }
}
