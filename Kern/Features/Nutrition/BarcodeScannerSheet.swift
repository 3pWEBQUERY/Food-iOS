import SwiftUI
import SwiftData
import VisionKit
import Vision

/// Barcode scannen → eigene Datenbank → eigener Katalog → Open Food Facts.
struct BarcodeScannerSheet: View {
    let meal: MealType
    let day: Date
    var onLogged: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var prefs

    @State private var phase: Phase = .scanning
    @State private var manualCode = ""
    @State private var foundFood: FoodItem?
    @State private var foundOrigin: FoodLookupOrigin?
    @State private var createForCode: String?
    @State private var scanCount = 0

    init(meal: MealType, day: Date, onLogged: (() -> Void)? = nil) {
        self.meal = meal
        self.day = day
        self.onLogged = onLogged
    }

    private enum Phase: Equatable {
        case scanning
        case looking(String)
        case notFound(String)
        case failed(String)
    }

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scannerArea
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, Theme.Space.s)

                statusArea
                    .padding(Theme.screenPadding)

                Spacer(minLength: 0)

                manualEntry
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, Theme.Space.m)
            }
            .background(Theme.background)
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: scanCount)
            .sheet(item: $foundFood, onDismiss: { phase = .scanning }) { food in
                FoodAmountSheet(food: food, meal: meal, day: day, source: .barcode,
                                originNote: foundOrigin.map { "Gefunden in: \($0.title)" }) { _ in
                    onLogged?()
                    dismiss()
                }
            }
            .sheet(item: Binding(get: { createForCode.map { NutritionBarcodeBox(code: $0) } }, set: { createForCode = $0?.code })) { box in
                NutritionCustomFoodEditor(barcode: box.code) { food in
                    createForCode = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        foundOrigin = .local
                        foundFood = food
                    }
                }
            }
        }
    }

    // MARK: Teile

    @ViewBuilder
    private var scannerArea: some View {
        if scannerAvailable {
            ZStack {
                NutritionDataScanner(isActive: phase == .scanning) { code in
                    guard phase == .scanning else { return }
                    scanCount += 1
                    Task { await lookup(code) }
                }
                if case .looking = phase {
                    Color.black.opacity(0.35)
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .background(Color.black)
            .accessibilityLabel("Kamera-Vorschau zum Scannen von Barcodes")
        } else {
            ZStack {
                Theme.surface
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Scanner nicht verfügbar")
                        .font(.headline)
                    Text("Auf diesem Gerät ist die Kamera nicht verfügbar oder der Zugriff wurde nicht erlaubt. Du kannst den Code unten eingeben.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.l)
                }
            }
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch phase {
        case .scanning:
            Text("Halte den Barcode der Verpackung in den Rahmen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .looking(let code):
            Text("Suche Produkt \(code) …")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .notFound(let code):
            Card {
                CardHeader(title: "Produkt nicht gefunden", symbol: "questionmark.circle", tint: Theme.warning)
                Text("Für den Barcode \(code) gibt es weder in deinem Katalog noch in Open Food Facts einen Eintrag. Du kannst das Produkt mit den Angaben der Verpackung selbst anlegen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Selbst anlegen") { createForCode = code }
                        .buttonStyle(.glassProminent)
                    Button("Erneut scannen") { phase = .scanning }
                        .buttonStyle(.glass)
                }
            }
        case .failed(let message):
            Card {
                CardHeader(title: "Abfrage fehlgeschlagen", symbol: "wifi.exclamationmark", tint: Theme.warning)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Erneut scannen") { phase = .scanning }
                    .buttonStyle(.glass)
            }
        }
    }

    private var manualEntry: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("Barcode eingeben", text: $manualCode)
                .keyboardType(.numberPad)
                .textContentType(.none)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            Button("Suchen") {
                let code = manualCode
                Task { await lookup(code) }
            }
            .buttonStyle(.glassProminent)
            .disabled(manualCode.filter(\.isNumber).count < 6)
        }
    }

    // MARK: Logik

    private func lookup(_ code: String) async {
        let clean = code.filter(\.isNumber)
        phase = .looking(clean)
        let result = await FoodRepository.lookup(barcode: clean, prefs: prefs, in: context)
        switch result {
        case .found(let food, let origin):
            foundOrigin = origin
            foundFood = food
        case .notFound(let c):
            phase = .notFound(c)
        case .failed(let message):
            phase = .failed(message)
        }
    }
}

/// Identifizierbarer Barcode für `sheet(item:)`.
private struct NutritionBarcodeBox: Identifiable {
    let code: String
    var id: String { code }
}

// MARK: - VisionKit-Scanner

private struct NutritionDataScanner: UIViewControllerRepresentable {
    var isActive: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if isActive && !controller.isScanning {
            try? controller.startScanning()
        } else if !isActive && controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var lastCode: String?
        private var lastDate = Date.distantPast

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    // Doppelte Erkennung desselben Codes kurz hintereinander ignorieren.
                    if value == lastCode && Date.now.timeIntervalSince(lastDate) < 3 { return }
                    lastCode = value
                    lastDate = .now
                    onCode(value)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                onCode(value)
            }
        }
    }
}
