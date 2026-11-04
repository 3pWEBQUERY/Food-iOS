import AuthenticationServices
import SwiftData
import SwiftUI

/// Übersicht aller Einstellungen. Wird im Heute-Tab gepusht oder als Sheet gezeigt.
struct SettingsView: View {
    @Environment(AppPreferences.self) private var prefs
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        List {
            Section {
                SettingsAccountHeader(profile: profiles.first)
            }

            Section("Persönlich") {
                link(.profile)
                link(.goals)
                link(.targets)
            }

            Section("App") {
                link(.modules)
                link(.dashboard)
                link(.units)
                link(.notifications)
            }

            Section("Verbindungen") {
                link(.health)
                link(.coach)
            }

            Section("Daten") {
                link(.privacy)
                link(.auditLog)
            }

            Section("Hilfe") {
                link(.tutorial)
                link(.about)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Einstellungen")
    }

    private func link(_ section: SettingsSection) -> some View {
        NavigationLink(value: AppDestination.settingsSection(section)) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                    if let subtitle = subtitle(for: section) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                SettingsIcon(symbol: section.symbol, tint: SettingsIcon.tint(for: section))
            }
        }
    }

    private func subtitle(for section: SettingsSection) -> String? {
        switch section {
        case .goals: profiles.first.map { $0.primaryGoal.title }
        case .targets: profiles.first.map { "\(Fmt.energyWithUnit(Double($0.calorieTarget), unit: prefs.energyUnit)) · \($0.proteinTargetG) g Protein" }
        case .modules: "\(prefs.enabledModules.count) aktiv"
        case .health: prefs.healthKitEnabled ? "Verbunden" : "Nicht verbunden"
        case .coach: prefs.aiProcessingConsent && prefs.hasBackend ? "Server-KI freigegeben" : "Nur auf dem Gerät"
        default: nil
        }
    }
}

/// Flaches, farbiges Symbol im Stil der iOS-Einstellungen.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    static func tint(for section: SettingsSection) -> Color {
        switch section {
        case .profile: Theme.weight
        case .goals: Theme.accent
        case .targets: Theme.training
        case .modules, .dashboard: Theme.protein
        case .units: Color(uiColor: .systemGray)
        case .health: Theme.fat
        case .notifications: Theme.warning
        case .coach: Theme.accent
        case .privacy: Color(uiColor: .systemGray)
        case .auditLog: Theme.supplement
        case .tutorial, .about: Color(uiColor: .systemGray2)
        }
    }
}

/// Kontostatus: Anmeldung mit Apple oder Testmodus.
private struct SettingsAccountHeader: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.colorScheme) private var colorScheme
    let profile: UserProfile?
    @State private var errorText: String?

    private var initials: String {
        let name = profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return parts.isEmpty ? "K" : parts.joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 54, height: 54)
                    .background(Theme.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName.isEmpty == false ? profile?.displayName ?? "" : "Dein Profil")
                        .font(.headline)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if prefs.appleUserID == nil {
                Text(prefs.isGuestMode
                     ? "Du nutzt Kern im Testmodus. Deine Daten bleiben ausschliesslich auf diesem Gerät. Mit einem Konto kannst du später sicher synchronisieren."
                     : "Melde dich an, um deine Daten später sicher zu synchronisieren. Kern funktioniert auch ohne Konto vollständig offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusText: String {
        if prefs.appleUserID != nil { return "Angemeldet mit Apple" }
        if prefs.isGuestMode { return "Testmodus · nur auf diesem Gerät" }
        return "Lokales Profil · ohne Konto"
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            prefs.appleUserID = credential.user
            prefs.isGuestMode = false
            if let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) {
                KeychainStore.set(token, for: KeychainStore.Keys.appleIdentityToken)
            }
            if let profile, profile.displayName.isEmpty, let given = credential.fullName?.givenName {
                profile.displayName = [given, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            }
            errorText = nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorText = "Die Anmeldung ist fehlgeschlagen. Bitte versuche es erneut."
        }
    }
}
