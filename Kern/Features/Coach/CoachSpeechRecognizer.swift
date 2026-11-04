import AVFoundation
import Foundation
import Observation
import Speech

/// Spracheingabe für den Coach (Speech-Framework, bevorzugt auf dem Gerät).
@MainActor
@Observable
final class CoachSpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var errorMessage: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer: SFSpeechRecognizer? = {
        if let swiss = SFSpeechRecognizer(locale: Locale(identifier: "de-CH")), swiss.isAvailable { return swiss }
        return SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    }()

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        errorMessage = nil
        transcript = ""

        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = "Spracherkennung ist nicht erlaubt. Du kannst sie in den iOS-Einstellungen aktivieren."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Kein Zugriff auf das Mikrofon. Du kannst ihn in den iOS-Einstellungen erlauben."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Die Spracherkennung ist gerade nicht verfügbar."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            Self.installTap(on: engine.inputNode, request: request)
            engine.prepare()
            try engine.start()

            audioEngine = engine
            self.request = request
            isRecording = true

            task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch {
            errorMessage = "Aufnahme konnte nicht gestartet werden."
            stop()
        }
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        audioEngine = nil
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Nicht isolierte Helfer (Callbacks laufen auf Hintergrund-Threads)

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startTask(recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            update(text, finished)
        }
    }
}
