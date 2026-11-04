import SwiftUI
import SwiftData
import PhotosUI
import Vision
import UIKit

/// Fotoerkennung von Mahlzeiten. Ergebnisse sind immer Schätzungen und müssen vor dem
/// Speichern geprüft werden. Serverseitige KI nur mit Backend und ausdrücklicher Zustimmung,
/// sonst einfache Erkennung auf dem Gerät.
struct PhotoFoodSheet: View {
    let day: Date
    var onLogged: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs
    @Environment(AppRouter.self) private var router

    @Query(filter: #Predicate<FoodItem> { $0.isHidden == false }) private var foods: [FoodItem]

    @State private var meal: MealType
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showsCamera = false
    @State private var isAnalyzing = false
    @State private var suggestions: [NutritionPhotoSuggestion] = []
    @State private var analysisNote: String?
    @State private var usedCloud = false

    init(meal: MealType, day: Date, onLogged: (() -> Void)? = nil) {
        self.day = day
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
    }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var included: [NutritionPhotoSuggestion] { suggestions.filter(\.isIncluded) }
    private var totalKcal: Double { included.reduce(0) { $0 + $1.nutrients.kcal } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    imageArea
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if imageData == nil {
                    Section {
                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                if cameraAvailable {
                                    Button {
                                        showsCamera = true
                                    } label: {
                                        Label("Foto aufnehmen", systemImage: "camera")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.glassProminent)
                                }
                                PhotosPicker(selection: $pickerItem, matching: .images) {
                                    Label("Mediathek", systemImage: "photo.on.rectangle")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text(privacyFooter)
                    }
                }

                if isAnalyzing {
                    Section {
                        HStack(spacing: 10) {
                            SwiftUI.ProgressView()
                            Text("Bild wird analysiert …").foregroundStyle(.secondary)
                        }
                    }
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach($suggestions) { $suggestion in
                            NutritionPhotoSuggestionRow(suggestion: $suggestion, energyUnit: prefs.energyUnit)
                        }
                        .onDelete { suggestions.remove(atOffsets: $0) }
                    } header: {
                        HStack {
                            Text("Erkannt")
                            Spacer()
                            QualityBadge(quality: .aiUnconfirmed)
                        }
                        .textCase(nil)
                    } footer: {
                        Text("KI-Schätzung – bitte prüfen. Zutaten und Mengen sind Vorschläge und keine gemessenen Nährwerte. Passe die Mengen an und entferne Falsches, bevor du speicherst.")
                    }

                    Section {
                        Picker("Mahlzeit", selection: $meal) {
                            ForEach(MealType.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }

                if let analysisNote {
                    Section {
                        InfoNote(text: analysisNote)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        Button("Stattdessen manuell suchen") {
                            router.present(.foodSearch(meal: meal, day: day))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Foto erkennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                if imageData != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Neues Foto") { reset() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !included.isEmpty {
                    PrimaryActionButton(title: "Geprüft · \(Fmt.energyWithUnit(totalKcal, unit: prefs.energyUnit)) speichern") {
                        save()
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, Theme.Space.xs)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await analyze(data)
                    }
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                NutritionCameraPicker { image in
                    showsCamera = false
                    if let data = image?.jpegData(compressionQuality: 0.8) {
                        Task { await analyze(data) }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Teile

    @ViewBuilder
    private var imageArea: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel("Ausgewähltes Foto")
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Fotografiere deine Mahlzeit")
                    .font(.headline)
                Text("Kern schlägt erkannte Lebensmittel und Portionen vor. Du prüfst und bestätigst jeden Vorschlag.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var privacyFooter: String {
        if prefs.hasBackend && prefs.aiProcessingConsent {
            return "Das Foto wird zur Analyse verschlüsselt an die Kern-KI übertragen und nicht für Werbung verwendet."
        }
        return "Die Erkennung läuft auf deinem Gerät. Für genauere Ergebnisse kann die Cloud-KI in den Einstellungen mit deiner Zustimmung aktiviert werden."
    }

    // MARK: Logik

    private func reset() {
        imageData = nil
        pickerItem = nil
        suggestions = []
        analysisNote = nil
    }

    private func analyze(_ data: Data) async {
        imageData = data
        suggestions = []
        analysisNote = nil
        isAnalyzing = true
        defer { isAnalyzing = false }

        if prefs.hasBackend && prefs.aiProcessingConsent,
           let remote = await NutritionVisionClient.analyze(data, baseURL: prefs.backendBaseURL), !remote.isEmpty {
            usedCloud = true
            suggestions = remote
            return
        }

        usedCloud = false
        let labels = await NutritionImageClassifier.classify(data)
        var result: [NutritionPhotoSuggestion] = []
        var usedNames = Set<String>()
        for label in labels {
            guard let term = NutritionImageClassifier.germanTerm(for: label.identifier) else { continue }
            guard let food = FoodRepository.search(foods, query: term, limit: 1).first,
                  !usedNames.contains(food.name) else { continue }
            usedNames.insert(food.name)
            let grams = food.servings.first?.grams ?? 150
            result.append(NutritionPhotoSuggestion(name: food.name, grams: grams, per100: food.per100,
                                                   foodID: food.id, confidence: Double(label.confidence)))
            if result.count >= 4 { break }
        }
        suggestions = result
        if result.isEmpty {
            analysisNote = "Auf diesem Foto konnten keine Lebensmittel sicher erkannt werden. Versuche es mit besserem Licht oder suche das Lebensmittel manuell."
        }
    }

    private func save() {
        let date = day.withCurrentTime()
        for s in included where s.grams > 0 {
            LogService.logCustom(name: s.name, nutrients: s.nutrients, grams: s.grams,
                                 amountLabel: "\(Fmt.number(s.grams)) g (geschätzt)", meal: meal, date: date,
                                 quality: .aiUnconfirmed, source: .photo, isEstimate: true, in: context)
        }
        onLogged?()
        dismiss()
    }
}

// MARK: - Vorschlag

struct NutritionPhotoSuggestion: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var grams: Double
    var per100: Nutrients
    var foodID: UUID?
    var confidence: Double
    var isIncluded = true

    var nutrients: Nutrients { per100.forGrams(grams) }
}

private struct NutritionPhotoSuggestionRow: View {
    @Binding var suggestion: NutritionPhotoSuggestion
    let energyUnit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Toggle(isOn: $suggestion.isIncluded) {
                    TextField("Bezeichnung", text: $suggestion.name)
                        .font(.body)
                }
                .toggleStyle(NutritionCheckToggleStyle())
            }
            HStack(spacing: Theme.Space.s) {
                Stepper(value: $suggestion.grams, in: 0...2000, step: 10) {
                    HStack(spacing: 4) {
                        TextField("g", value: $suggestion.grams, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .monospacedDigit()
                            .frame(maxWidth: 56)
                        Text("g").foregroundStyle(.secondary)
                        Spacer()
                        Text("≈ \(Fmt.energyWithUnit(suggestion.nutrients.kcal, unit: energyUnit))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline)
            .opacity(suggestion.isIncluded ? 1 : 0.4)
            Text("Sicherheit der Erkennung: \(Fmt.percent(suggestion.confidence))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Runde Checkbox im iOS-Stil.
private struct NutritionCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Button {
                configuration.isOn.toggle()
            } label: {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(configuration.isOn ? "Übernehmen" : "Nicht übernehmen")
            configuration.label
        }
    }
}

// MARK: - Erkennung

enum NutritionImageClassifier {
    struct Classification: Sendable {
        let identifier: String
        let confidence: Float
    }

    /// Bildklassifikation auf dem Gerät (Vision).
    static func classify(_ data: Data) async -> [Classification] {
        await Task.detached(priority: .userInitiated) { () -> [Classification] in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: data, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            let observations = request.results ?? []
            return observations
                .filter { $0.confidence > 0.05 }
                .prefix(30)
                .map { Classification(identifier: $0.identifier.lowercased(), confidence: $0.confidence) }
        }.value
    }

    /// Zuordnung englischer Vision-Klassen zu deutschen Suchbegriffen im lokalen Katalog.
    private static let terms: [String: String] = [
        "banana": "Banane", "apple": "Apfel", "orange": "Orange", "pear": "Birne", "strawberry": "Erdbeeren",
        "grape": "Trauben", "pineapple": "Ananas", "mango": "Mango", "watermelon": "Wassermelone",
        "kiwi": "Kiwi", "cherry": "Kirschen", "peach": "Pfirsich", "blueberry": "Heidelbeeren",
        "pizza": "Pizza Margherita", "salad": "Gemischter Salat", "bread": "Halbweissbrot",
        "baguette": "Halbweissbrot", "croissant": "Buttergipfeli", "pretzel": "Laugenbrezel",
        "pasta": "Teigwaren gekocht", "spaghetti": "Spaghetti Bolognese", "lasagna": "Lasagne",
        "rice": "Reis gekocht", "sushi": "Sushi Maki", "egg": "Ei", "omelet": "Ei", "omelette": "Ei",
        "cheese": "Emmentaler", "sandwich": "Brötchen", "hamburger": "Hamburger", "burger": "Hamburger",
        "french_fries": "Pommes frites", "fries": "Pommes frites", "soup": "Gemüsesuppe",
        "cake": "Rüeblitorte", "pie": "Apfelwähe", "ice_cream": "Glace Vanille", "chocolate": "Milchschokolade",
        "coffee": "Cappuccino", "espresso": "Espresso", "tea": "Schwarztee", "beer": "Bier", "wine": "Rotwein",
        "steak": "Rindsplätzli", "chicken": "Pouletbrust", "sausage": "Kalbsbratwurst", "hot_dog": "Wienerli",
        "salmon": "Lachs", "fish": "Kabeljau", "shrimp": "Crevetten", "tofu": "Tofu",
        "broccoli": "Broccoli", "carrot": "Karotte", "tomato": "Tomate", "cucumber": "Gurke",
        "potato": "Kartoffeln gekocht", "avocado": "Avocado", "corn": "Mais", "mushroom": "Champignons",
        "yogurt": "Joghurt nature", "oatmeal": "Haferflocken", "porridge": "Haferflocken", "muesli": "Birchermüesli",
        "cereal": "Cornflakes", "nut": "Mandeln", "almond": "Mandeln", "walnut": "Baumnüsse",
        "kebab": "Döner Kebab", "fondue": "Käsefondue", "pancake": "Brötchen", "milk": "Vollmilch",
        "juice": "Orangensaft", "smoothie": "Smoothie"
    ]

    static func germanTerm(for identifier: String) -> String? {
        let id = identifier.lowercased()
        if let exact = terms[id] { return exact }
        // Teiltreffer, z. B. „green_salad“ → „salad“
        let parts = id.split(whereSeparator: { $0 == "_" || $0 == " " }).map(String.init)
        for part in parts.reversed() {
            if let match = terms[part] { return match }
        }
        return nil
    }
}

/// Optionale serverseitige Fotoerkennung (`POST /v1/vision/food`).
enum NutritionVisionClient {
    static func analyze(_ data: Data, baseURL: String) async -> [NutritionPhotoSuggestion]? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/v1/vision/food") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainStore.get(KeychainStore.Keys.backendSession) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = ["image": data.base64EncodedString(), "mimeType": "image/jpeg", "locale": "de-CH"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }

        return items.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let grams = OpenFoodFactsClient.number(item["grams"]) ?? 100
            let factor = grams > 0 ? 100 / grams : 1
            // Server liefert Werte für die geschätzte Menge → auf 100 g umrechnen.
            let total = Nutrients(kcal: OpenFoodFactsClient.number(item["kcal"]) ?? 0,
                                  protein: OpenFoodFactsClient.number(item["protein"]) ?? 0,
                                  carbs: OpenFoodFactsClient.number(item["carbs"]) ?? 0,
                                  fat: OpenFoodFactsClient.number(item["fat"]) ?? 0)
            return NutritionPhotoSuggestion(name: name, grams: grams, per100: total.scaled(by: factor), foodID: nil,
                                            confidence: OpenFoodFactsClient.number(item["confidence"]) ?? 0.5)
        }
    }
}

// MARK: - Kamera

private struct NutritionCameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
