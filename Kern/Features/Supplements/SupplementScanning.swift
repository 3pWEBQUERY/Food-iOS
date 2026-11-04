import SwiftUI
import UIKit
import Vision
import VisionKit

// MARK: - Barcode

/// Barcode-Scanner (VisionKit) für Supplement-Verpackungen.
struct SupplementBarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

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
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var didFinish = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFinish else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, !value.isEmpty {
                    didFinish = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(value)
                    return
                }
            }
        }
    }
}

/// Scanner-Sheet mit manueller Eingabe als Alternative.
struct SupplementScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.m) {
                if SupplementBarcodeScanner.isAvailable {
                    SupplementBarcodeScanner { code in
                        dismiss()
                        onCode(code)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .frame(maxHeight: 420)
                } else {
                    ContentUnavailableView("Scanner nicht verfügbar", systemImage: "barcode.viewfinder",
                                           description: Text("Gib den Barcode manuell ein."))
                }
                HStack {
                    TextField("Barcode manuell eingeben", text: $manualCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Suchen") {
                        let code = manualCode.trimmingCharacters(in: .whitespaces)
                        dismiss()
                        onCode(code)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(manualCode.trimmingCharacters(in: .whitespaces).count < 6)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.screenPadding)
            .background(Theme.background)
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Externe Abfrage

enum SupplementLookup {
    struct Result {
        var name: String
        var brand: String
    }

    /// Abfrage bei Open Food Facts (nur Name/Marke). Daten unter ODbL.
    static func openFoodFacts(barcode: String) async -> Result? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,product_name_de,brands") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Kern-iOS/1.0", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let product = json["product"] as? [String: Any] else { return nil }
        let nameDE = (product["product_name_de"] as? String) ?? ""
        let name = nameDE.isEmpty ? ((product["product_name"] as? String) ?? "") : nameDE
        let brand = ((product["brands"] as? String) ?? "").split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !name.isEmpty else { return nil }
        return Result(name: name, brand: brand)
    }
}

// MARK: - Etikett-Texterkennung

enum SupplementLabelReader {
    struct Parsed {
        var nameCandidate: String?
        var ingredients: [SupplementIngredient]
        var lineCount: Int
    }

    /// Erkennt Text auf dem Foto eines Etiketts (auf dem Gerät, ohne Upload).
    static func read(_ image: UIImage) async -> Parsed {
        guard let cgImage = image.cgImage else { return Parsed(nameCandidate: nil, ingredients: [], lineCount: 0) }
        let orientation = cgOrientation(image.imageOrientation)
        let lines: [String] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["de-DE", "en-US", "fr-FR", "it-IT"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try? handler.perform([request])
                let text = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: text)
            }
        }
        return parse(lines)
    }

    static func parse(_ lines: [String]) -> Parsed {
        let pattern = #"^\s*([A-Za-zÄÖÜäöüéè][A-Za-zÄÖÜäöüéè0-9 .\-/()]{1,40}?)\s*[:\-]?\s+(\d+(?:[.,]\d+)?)\s*(mg|µg|μg|mcg|g|IE|I\.E\.|IU)\b"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        var ingredients: [SupplementIngredient] = []
        var seen = Set<String>()
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let regex, let match = regex.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let amountRange = Range(match.range(at: 2), in: line),
                  let unitRange = Range(match.range(at: 3), in: line) else { continue }
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            let amount = Double(line[amountRange].replacingOccurrences(of: ",", with: ".")) ?? 0
            var unit = String(line[unitRange])
            switch unit.lowercased() {
            case "mcg", "μg": unit = "µg"
            case "i.e.", "iu": unit = "IE"
            case "ie": unit = "IE"
            default: unit = unit.lowercased() == "g" ? "g" : unit.lowercased()
            }
            let lowered = name.lowercased()
            let ignored = ["portion", "tagesdosis", "kapsel", "tablette", "inhalt", "nettogewicht", "energie", "brennwert", "pro"]
            guard amount > 0, !ignored.contains(where: { lowered.hasPrefix($0) }), !seen.contains(lowered) else { continue }
            seen.insert(lowered)
            ingredients.append(SupplementIngredient(name: name, amount: amount, unit: unit))
        }
        let nameCandidate = lines.first { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && !line.contains(where: \.isNumber) && line.count <= 40
        }
        return Parsed(nameCandidate: nameCandidate, ingredients: ingredients, lineCount: lines.count)
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

/// Kamera für Etikett-Fotos.
struct SupplementCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SupplementCameraPicker
        init(_ parent: SupplementCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
