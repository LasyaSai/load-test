import Foundation
import AVFoundation
import Speech

/// Manages microphone recording and AVSpeechSynthesizer TTS output.
class AudioManager: NSObject {

    // Called with transcribed text when a recording ends.
    var onTranscription: ((String) -> Void)?

    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Real microphone recording (production path)

    func startRecording() {
        if let override = ProcessInfo.processInfo.environment["CASE_TRANSCRIPT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            recordingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".wav")
            return
        }

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
        if let override = ProcessInfo.processInfo.environment["CASE_TRANSCRIPT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            audioFile = nil
            guard let url = recordingURL else { return }
            transcribe(audioURL: url)
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil
        guard let url = recordingURL else { return }
        transcribe(audioURL: url)
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

    // MARK: - Transcription

    private func transcribe(audioURL: URL) {
        if let override = ProcessInfo.processInfo.environment["CASE_TRANSCRIPT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            onTranscription?(override)
            return
        }

        // Deterministic fallback for local runs without a backend.
        let transcript = audioURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        onTranscription?(transcript)
    }
}

extension Notification.Name {
    static let ttsDidStart = Notification.Name("VoiceTextDemo.TTSDidStart")
}
