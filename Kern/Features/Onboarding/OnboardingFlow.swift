import SwiftUI
import SwiftData
import AuthenticationServices

/// Kurzes, animiertes Onboarding. Alles, was nicht sofort gebraucht wird, kann später ergänzt werden.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppPreferences.self) private var prefs
    @State private var model = OnboardingModel()
    @State private var isForward = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.step != .welcome {
                    header
                        .transition(.opacity)
                }

                ZStack {
                    stepView
                        .id(model.step)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.step != .welcome {
                    footer
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .animation(.smooth(duration: 0.45), value: model.step)
        .sensoryFeedback(.impact(weight: .light), trigger: model.step)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome: OnboardingWelcomeStep(model: model, onContinue: advance)
        case .goals: OnboardingGoalsStep(model: model)
        case .aboutYou: OnboardingAboutStep(model: model)
        case .activity: OnboardingActivityStep(model: model)
        case .goalDetails: OnboardingGoalDetailsStep(model: model)
        case .nutrition: OnboardingNutritionStep(model: model)
        case .modules: OnboardingModulesStep(model: model)
        case .summary: OnboardingSummaryStep(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Zurück", size: 40) {
                isForward = false
                model.back()
            }
            LinearMeter(progress: model.progress, tint: Theme.accent, height: 4, showsOverflow: false)
                .accessibilityLabel("Fortschritt")
            Text("\(model.stepIndex)/\(model.steps.count - 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.s)
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.xs) {
            PrimaryActionButton(
                title: model.step == .summary ? "Los geht’s" : "Weiter",
                systemImage: model.step == .summary ? nil : "arrow.right",
                isEnabled: model.canContinue
            ) {
                if model.step == .summary {
                    model.complete(context: context, preferences: prefs)
                } else {
                    advance()
                }
            }
            if model.step != .summary && model.step != .goals && model.step != .aboutYou {
                Button("Später ergänzen") { advance() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, Theme.Space.s)
        .padding(.top, Theme.Space.xs)
    }

    private func advance() {
        isForward = true
        model.next()
    }
}

// MARK: - Bausteine

/// Gemeinsamer Rahmen eines Onboarding-Schritts.
struct OnboardingPage<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Auswählbare Zeile/Kachel mit Symbol, Titel und Untertitel.
struct OnboardingOption: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    let isSelected: Bool
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(isSelected ? Theme.accent : Theme.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if let badge { Badge(text: badge, tint: Theme.accent) }
                    }
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Color(uiColor: .tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Theme.Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Grosse Zahleneingabe mit Stepper-Tasten.
struct OnboardingNumberInput: View {
    let title: String
    @Binding var value: Double
    let unit: String
    var step: Double = 1
    var range: ClosedRange<Double>
    var fractionDigits: Int = 0

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.s) {
                stepButton("minus") { value = max(range.lowerBound, (value - step).rounded(toNearest: step)) }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("", value: $value, format: .number.precision(.fractionLength(0...fractionDigits)).locale(Fmt.locale))
                        .font(.metricMedium)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                        .focused($focused)
                        .fixedSize()
                    Text(unit).font(.body.weight(.medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                stepButton("plus") { value = min(range.upperBound, (value + step).rounded(toNearest: step)) }
            }
            .padding(Theme.Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { value = value.clamped(range) }
        }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focused = false }
                }
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(symbol == "plus" ? "\(title) erhöhen" : "\(title) verringern")
    }
}

// MARK: - Willkommen

struct OnboardingWelcomeStep: View {
    @Bindable var model: OnboardingModel
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var signInError: String?

    private let pillars: [(String, String, String)] = [
        ("fork.knife", "Ernährung", "Schnell erfassen – Suche, Barcode, Foto oder Sprache"),
        ("dumbbell", "Training", "Gym-Tagebuch mit Plänen, Pausen und Rekorden"),
        ("chart.line.uptrend.xyaxis", "Fortschritt", "Zusammenhänge statt einzelner Zahlen")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Space.xl)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                KernMark(size: 56)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.85, anchor: .bottomLeading)
                Text("Kern")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                Text("Tracke nicht nur, was du isst und trainierst. Verstehe, wie du dich entwickelst.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }

            Spacer(minLength: Theme.Space.xl)

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ForEach(Array(pillars.enumerated()), id: \.offset) { index, pillar in
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        Image(systemName: pillar.0)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pillar.1).font(.headline)
                            Text(pillar.2).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.smooth(duration: 0.6).delay(0.25 + Double(index) * 0.1), value: appeared)
                }
            }

            Spacer(minLength: Theme.Space.xl)

            VStack(spacing: Theme.Space.s) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(Capsule())

                Button {
                    model.isGuest = true
                    onContinue()
                } label: {
                    Text("Ohne Konto ausprobieren")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                if let signInError {
                    Text(signInError).font(.footnote).foregroundStyle(Theme.warning)
                }

                Text("Deine Gesundheitsdaten bleiben auf deinem Gerät, bis du etwas anderes entscheidest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.Space.xxs)
            }
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, Theme.screenPadding + 8)
        .padding(.bottom, Theme.Space.m)
        .onAppear {
            withAnimation(.smooth(duration: 0.7)) { appeared = true }
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            model.appleUserID = credential.user
            if let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) {
                KeychainStore.set(token, for: KeychainStore.Keys.appleIdentityToken)
            }
            if let given = credential.fullName?.givenName, model.name.isEmpty {
                model.name = given
            }
            model.isGuest = false
            onContinue()
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            signInError = "Anmeldung nicht möglich. Du kannst Kern auch ohne Konto ausprobieren."
        }
    }
}

/// Wortmarke: ein Kreis mit Kern – flach, ohne Effekte.
struct KernMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.accent, lineWidth: size * 0.11)
            Circle()
                .fill(Theme.accent)
                .frame(width: size * 0.36, height: size * 0.36)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
