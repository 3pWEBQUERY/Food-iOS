# Kern – Architektur & Konventionen

Kern ist eine native iOS-26-App (Swift 5 Sprachmodus, SwiftUI, SwiftData, Liquid Glass).
Alle Kernfunktionen laufen offline. Cloud-Funktionen (Backend, serverseitige KI) sind über
klar abgegrenzte Protokolle angebunden und optional.

## Verzeichnisstruktur

```
Kern/                       App-Target (Xcode synchronisierter Ordner)
  App/                      Einstieg, Router, Tab-Navigation, Sheet- und Ziel-Zuordnung
  Core/Design/              Theme (Tokens), Components, Formatters
  Core/Models/              SwiftData-Modelle und Enums
  Core/Services/            Persistence, LogService, EnergyCalculator, AdaptiveEnergyEstimator,
                            ProfileService, HealthKitManager, NotificationManager, AuditLog, Seeds
  Features/<Bereich>/       Feature-Module (Onboarding, Today, Nutrition, Training, Progress,
                            Supplements, Cycle, Coach, Settings, QuickAdd, Habits)
KernWidgets/                Widget-Extension (WidgetKit)
Shared/                     Code für App + Widget (WidgetSnapshot, App Intents)
Config/                     Info.plist-Ergänzungen und Entitlements
```

## Design-Regeln (verbindlich)

- **Keine Schatten, keine Farbverläufe.** Keine `.shadow`, kein `LinearGradient`/`RadialGradient`/`AngularGradient`.
- **Liquid Glass nur auf der Steuerungsebene**: Tab-Bar, Toolbars (automatisch), schwebende Buttons
  (`GlassIconButton`, `.glassEffect(...)`), primäre Aktionen (`.buttonStyle(.glassProminent)` /
  `PrimaryActionButton`), sekundäre Aktionen (`.buttonStyle(.glass)`), Bottom-Accessory, Timer-Pillen.
  Mehrere benachbarte Glas-Elemente in einen `GlassEffectContainer` legen.
- **Inhalte auf flachen Flächen**: `Card { … }` (Theme.surface, Radius 22, continuous) auf `Theme.background`.
  Listen/Formulare: native `List`/`Form` mit `.insetGrouped`-Stil.
- Farben ausschliesslich aus `Theme` (accent, protein, carbs, fat, water, training, weight, supplement, cycle,
  warning, positive). Farbe sparsam einsetzen – Typografie und Abstand tragen die Hierarchie.
- Zahlen: `.monospacedDigit()`, Kennzahlen mit `Font.metricLarge/Medium/Small`, `.contentTransition(.numericText())`.
- Formatierung immer über `Fmt` (Schweizer Schreibweise 1’250, Komma-Dezimalen). Gewicht über
  `prefs.weightUnit`, Energie über `prefs.energyUnit`.
- Sprache: Deutsch in Schweizer Rechtschreibung (kein „ß“: „Grösse“, „Masse“, „gemäss“). Du-Form. Kurz, sachlich.
- Animationen dezent: `.smooth`, `.snappy`, `symbolEffect`, `sensoryFeedback`.
- Barrierefreiheit: Dynamic Type (Text-Styles statt fixer Grössen ausser Kennzahlen), `accessibilityLabel`
  für Icon-Buttons, Charts mit `accessibilityLabel/Value`, Tap-Flächen ≥ 44 pt.
- Hinweise/Disclaimer: `InfoNote`. KI-Schätzungen immer als solche kennzeichnen (`QualityBadge(.aiUnconfirmed)`).

## Datenmodell (SwiftData)

- Enums werden als `…Raw: String` gespeichert, mit typisierter Computed Property.
- Strukturierte Werte (Nährwerte, Zutaten, Vorlagenübungen, Inhaltsstoffe) als `Data` (JSON) mit
  Computed Property (`ModelCoding`). Keine Codable-Structs direkt als SwiftData-Attribute.
- Tagesbezogene Einträge haben `dayKey` (`DayKey.make(date)` → „yyyy-MM-dd“) für einfache `#Predicate`s.
- `FoodLogEntry` speichert einen Nährwert-Schnappschuss pro 100 g (`per100`) + `grams` →
  historische Einträge ändern sich nicht bei Katalogkorrekturen.
- Zielwechsel über `ProfileService.changeGoals` – erzeugt eine neue `GoalPhase`, löscht nie Daten.
- Schreib-Operationen für Einträge laufen über `LogService` (Protokoll, Health, Widgets inklusive).
- Rückgängig: `LogService.undo(auditEntry, in:)`.

## Navigation

- `AppRouter` (Environment): `selectedTab`, `present(_ sheet: AppSheet)`, `open(_ destination: AppDestination)`,
  `isWorkoutPresented`, `nutritionDay`.
- Jede Sheet-View bringt ihren eigenen `NavigationStack` mit (ausser `QuickAddSheet`, auch dieser hat einen).
- Push-Ziele sind in `MainTabView.swift → AppDestinationView` registriert. Innerhalb der App mit
  `NavigationLink(value: AppDestination.x)` navigieren.

## Environment-Objekte

`AppPreferences`, `AppRouter`, `WorkoutStore`, `HealthKitManager` – jeweils via `@Environment(Type.self)`.
`\.modelContext` für SwiftData. Profil: `@Query private var profiles: [UserProfile]` → `profiles.first`.

## View-Verträge (Name → Datei-Bereich)

| View / Typ | Bereich |
|---|---|
| `NutritionView`, `FoodSearchView(meal:day:)`, `BarcodeScannerSheet(meal:day:)`, `PhotoFoodSheet(meal:day:)`, `WaterView`, `WaterQuickSheet`, `RecipesView`, `SavedMealsView`, `FoodSeed.makeItems()` | Features/Nutrition |
| `TrainingView`, `ExerciseLibraryView`, `ExerciseDetailView(exerciseID:)`, `WorkoutHistoryView`, `WorkoutSessionDetailView(sessionID:)`, `GymProfilesView`, `PlanGeneratorView`, `PlanDetailView(planID:)`, `ActiveWorkoutView`, `ActiveWorkoutAccessory`, `WorkoutStore`, `ExerciseSeed`, `NextWorkoutCard`, `TrainingWeekCard`, `StrengthCard` | Features/Training |
| `ProgressHubView`, `WeightView`, `WeightEntrySheet`, `MeasurementsView`, `MeasurementEntrySheet`, `BodyAvatarView`, `ProgressPhotosView`, `WeeklyReportView`, `EnergyInsightView`, `InsightEngine`, `WeightTrendCard`, `WeeklyInsightCard`, `MeasurementsCard` | Features/Progress |
| `SupplementsView`, `SupplementsTodayCard` | Features/Supplements |
| `CycleView`, `CycleTodayCard` | Features/Cycle |
| `CoachView(prefill:)`, Coach-Engine, `SettingsView`, `SettingsSectionView(section:)`, `AuditLogView`, `WidgetBridge`, Widgets | Features/Coach, Features/Settings, Shared, KernWidgets |
| `OnboardingFlow`, `TutorialOverlay`, `TodayView`, `DashboardEditorView`, `QuickAddSheet`, `HabitsView` | Features/Onboarding, Today, QuickAdd, Habits |

## Backend-Schnittstelle (optional)

`AppPreferences.backendBaseURL` (leer = lokal). Erwartete Endpunkte (Railway, modularer API-Service):

- `GET  /v1/foods/barcode/{code}` – eigener Katalog (vor Open Food Facts)
- `POST /v1/foods/submissions` – Nutzer-Einreichung zur Prüfung
- `POST /v1/coach/messages` – serverseitige KI; Antwort enthält `text` und strukturierte `actions`
- `POST /v1/vision/food` – Fotoerkennung (Vorschläge, immer als Schätzung)
- `POST /v1/sync` – Cloud-Synchronisation (Konfliktbehandlung serverseitig, last-writer-wins pro Feld mit `updatedAt`)

Die App validiert alle KI-Aktionen lokal (Wertebereiche, Vollständigkeit, Bestätigungspflicht), bevor sie angewendet werden.
