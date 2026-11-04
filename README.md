# Kern – Ernährung, Training & Fortschritt für iOS

> Tracke nicht nur, was du isst und trainierst. Verstehe, wie du dich entwickelst.

Kern ist eine native All-in-One-App für Ernährung, Krafttraining, Gewichtsmanagement, Supplements
und Körperentwicklung – gebaut mit **SwiftUI für iOS 26** und dem **Liquid-Glass-Design**.

## Design

- **Liquid Glass nur dort, wo Apple es vorsieht:** Tab-Bar (minimiert sich beim Scrollen), Toolbars,
  das Bottom-Accessory (Coach-Zugang bzw. laufendes Training), schwebende Aktionen, Pausentimer, primäre Buttons.
- **Inhalte auf ruhigen, flachen Flächen** – keine Schatten, keine Farbverläufe, keine dekorativen Effekte.
- Eine Markenfarbe, gezielt eingesetzte Funktionsfarben (Protein, Kohlenhydrate, Fett, Wasser, Training).
- Hell-/Dunkelmodus, Dynamic Type, VoiceOver-Labels, Schweizer Schreibweise (1’250 kcal, „Grösse“).

## Funktionsumfang (iOS-App)

| Bereich | Umgesetzt |
|---|---|
| Onboarding | Sign in with Apple oder Testmodus ohne Konto, Ziele (Mehrfachauswahl + Hauptziel), Basisdaten, physiologische Angabe getrennt von Geschlechtsidentität, zielabhängige Detailfragen, Ernährungspräferenzen, Modulauswahl, berechneter Start inkl. Herleitung, überspringbares Tutorial |
| Dashboard | Zielabhängige Standardkarten, frei anordnen/ein-/ausblenden, Module-Zugang |
| Ernährung | Tagebuch nach Mahlzeiten, Makros + Mikros, Suche (lokal + Open Food Facts), Barcode-Scanner, Foto-Erkennung (als Schätzung gekennzeichnet), Schnelleintrag, eigene Lebensmittel, Rezepte (pro Portion / pro 100 g), gespeicherte Mahlzeiten, Tag kopieren, Wasser inkl. Getränke ohne Doppelerfassung |
| Energie | Mifflin-St.-Jeor, Müller (Gewicht / Körperzusammensetzung), Katch-McArdle, nachvollziehbare Auswahlregel, Sicherheitsregeln (Defizitgrenzen, Mindestwerte, Schwangerschaft/Stillzeit, < 18 J., BMI < 18.5), adaptive Bedarfsschätzung mit Vorschlag zum Bestätigen |
| Datenqualität | Status Verifiziert / Hersteller / Referenzwert / Community / KI-unbestätigt / Unvollständig, ODbL-Kennzeichnung, Nährwert-Schnappschuss pro Tagebucheintrag |
| Training | Pläne & Vorlagen, Gym-Tagebuch (Aufwärm-, Arbeits-, Drop-Sätze, Supersätze, RPE/RIR), Pausentimer, Rekorde & e1RM, Übungsbibliothek mit Filtern und Gerätemarken, gerätespezifische Historie, Gym-Profile, regelbasierter Plan-Generator, Progressionsvorschläge zum Annehmen/Ablehnen, vollständig offline |
| Fortschritt | Gewichtstrend (geglättet), gemeinsame Fortschrittslogik, Wochenanalyse mit Beobachtung/Schätzung/Vorschlag, Zielphasen-Historie, Körpermasse, Fortschrittsfotos, optionaler 3D-Körper (aktuell/Ziel, vorher/nachher, Überlagerung), Export |
| Supplements | Routinen, Einnahmebestätigung, Vorrat & Warnung, Inhaltsstoff-Summen und Überschneidungen – ohne Dosierungsempfehlungen |
| Zyklus | Optional, Face-ID-Schutz möglich, Kalender, Symptome, Wohlbefinden, Auswertung nur mit Zustimmung |
| KI-Coach | Chat mit Text, Sprache und Bild; erkennt Absichten („Heute 100,2 kg gewogen …“) und erzeugt strukturierte Aktionen mit Vorschau, Validierung, Bestätigung, Protokoll und Rückgängig; steuert Navigation und Einstellungen |
| Apple-Ökosystem | HealthKit (Gewicht, Schritte, Aktivität, Ernährung, Wasser, Trainings, Duplikatschutz), Widgets (Kalorien, Wasser mit Direkt-Button, Training, Gewicht, Schnellaktion), App Shortcuts, Deep Links `kern://` |
| Datenschutz | Lokale, verschlüsselte Speicherung (Data Protection), separate KI-Zustimmung, vollständiger Export, vollständige Löschung, Änderungsprotokoll |

## Projekt öffnen

Voraussetzungen: **Xcode 26** (iOS 26 SDK).

1. `Kern.xcodeproj` öffnen.
2. Unter *Signing & Capabilities* für beide Targets (`Kern`, `KernWidgetsExtension`) dein Team wählen.
   Bei Bedarf Bundle-IDs (`ch.kernapp.ios`) und App Group (`group.ch.kernapp.ios`) anpassen.
3. Scheme `Kern` auf einem iPhone oder Simulator starten.

Das Projekt nutzt synchronisierte Ordner: neue Dateien in `Kern/`, `Shared/` oder `KernWidgets/`
werden automatisch übernommen. Alternativ lässt es sich mit `xcodegen generate` aus `project.yml` erzeugen.

## Architektur

Siehe [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

- **SwiftUI + SwiftData**, offline-first. Alle Tracking- und Trainingsfunktionen laufen ohne Internet.
- **Core** (Design-Tokens, Modelle, Services) und **Features** (je Bereich ein Modul).
- **LogService** bündelt alle Schreibvorgänge → Protokoll, Apple Health und Widgets bleiben konsistent.
- **KI hinter Protokollen:** Der Coach arbeitet lokal regelbasiert; ist ein Backend konfiguriert und die
  Zustimmung erteilt, wird eine austauschbare serverseitige KI genutzt. Jede KI-Aktion wird lokal validiert.

## Stand & bekannte Einschränkungen

- Der Code wurde ohne Xcode erstellt und nur syntaktisch geprüft – beim ersten Build in Xcode 26
  können einzelne Typfehler auftreten, die sich schnell beheben lassen.
- Der KI-Coach arbeitet ohne Backend lokal und regelbasiert; Foto- und Etiketterkennung auf dem Gerät
  sind grob und immer als Schätzung markiert.
- Lebensmittel-Basisdaten sind generische Referenzwerte; Markenprodukte kommen live über Open Food Facts.
- Progressionsvorschläge und Deload-Status liegen in UserDefaults (noch nicht synchronisierbar).
- Der 3D-Körper ist eine illustrative SceneKit-Figur aus Grundformen, keine Körpervermessung.

## Nächste Schritte (ausserhalb dieser iOS-App)

- Backend (modularer API-Service auf Railway, PostgreSQL, Railway Bucket) gemäss Schnittstellen in `docs/ARCHITECTURE.md`
- Administrationsbereich und Website (Next.js)
- Cloud-Synchronisation mit Konfliktbehandlung, StoreKit-2-Abonnements
- Apple-Watch-App (nach dem App-Release), Community-Funktionen, fachlich geprüftes Reha-Modul
