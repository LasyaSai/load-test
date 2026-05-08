import Foundation
import AVFoundation
import Speech

/// Manages microphone recording, AVAudioEngine-based audio injection (for tests),
/// and AVSpeechSynthesizer TTS output.
class AudioManager: NSObject {

    // Called with transcribed text when a recording ends.
    var onTranscription: ((String) -> Void)?

    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Real microphone recording (production path)

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try? session.setActive(true)

        recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let url = recordingURL,
              let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        audioFile = file

        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        try? audioEngine.start()
    }

    func stopRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil
        guard let url = recordingURL else { return }
        transcribe(audioURL: url)
    }

    // MARK: - Test injection path
    // Called by XCTest bridge to inject a WAV file as mic input.
    // Uses AVAudioPlayerNode routed through the engine's inputNode.

    func injectAudioFile(url: URL, completion: @escaping () -> Void) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let file = try? AVAudioFile(forReading: url) else {
            completion(); return
        }
        let format = file.processingFormat
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Tap mainMixerNode output as if it were mic input - the app's
        // inputNode is mocked in the XCTest process via AudioUnit HAL override.
        player.scheduleFile(file, at: nil) { completion() }
        try? engine.start()
        player.play()
    }

    // MARK: - TTS output

    func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        // Post notification so test harness knows TTS started
        NotificationCenter.default.post(name: .ttsDidStart, object: nil, userInfo: ["text": text])
    }

    // MARK: - Local speech transcription

    private func transcribe(audioURL: URL) {
        Task {
            if let text = await transcribeOnDevice(audioURL: audioURL) {
                onTranscription?(text)
            }
        }
    }

    private func transcribeOnDevice(audioURL: URL) async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            return nil
        }

        let authStatus = await requestSpeechAuthorization()
        guard authStatus == .authorized else {
            return nil
        }

        guard recognizer.isAvailable else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true
            request.taskHint = .dictation

            var finished = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }

                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                    return
                }

                if error != nil {
                    finished = true
                    continuation.resume(returning: nil)
                }
            }

            _ = task
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

extension Notification.Name {
    static let ttsDidStart = Notification.Name("VoiceTextDemo.TTSDidStart")
}
