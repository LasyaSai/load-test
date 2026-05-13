import Foundation
import AVFoundation
import Speech

/// Manages microphone recording, injected fixture audio, and AVSpeechSynthesizer output.
class AudioManager: NSObject, AVSpeechSynthesizerDelegate {

    var onTranscription: ((String) -> Void)?
    var onCaptureFinished: ((String) -> Void)?

    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var injectedAudioURL: URL?
    private var injectionEngine: AVAudioEngine?
    private var injectionPlayer: AVAudioPlayerNode?
    private var captureRecorder: AVAudioRecorder?
    private var captureURL: URL?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Configuration

    func setInjectedAudioURL(_ url: URL?) {
        injectedAudioURL = url
    }

    // MARK: - Recording

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)

        recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        captureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_captured.wav")

        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let url = recordingURL,
              let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        audioFile = file

        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        try? audioEngine.start()
        startCaptureIfPossible()
    }

    func stopRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil

        guard let url = recordingURL else { return }
        transcribe(audioURL: url)
    }

    // MARK: - Test injection

    func injectAudioFile(url: URL, completion: @escaping () -> Void) {
        injectedAudioURL = url

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        injectionEngine = engine
        injectionPlayer = player
        engine.attach(player)

        guard let file = try? AVAudioFile(forReading: url) else {
            completion()
            return
        }

        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        player.scheduleFile(file, at: nil) {
            self.injectionPlayer?.stop()
            self.injectionEngine?.stop()
            self.injectionPlayer = nil
            self.injectionEngine = nil
            completion()
        }

        do {
            try engine.start()
            player.play()
        } catch {
            self.injectionPlayer = nil
            self.injectionEngine = nil
            completion()
        }
    }

    // MARK: - TTS output

    func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        NotificationCenter.default.post(name: .ttsDidStart, object: nil, userInfo: ["text": text])
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        captureRecorder?.stop()
        if let path = captureURL?.path {
            onCaptureFinished?(path)
        }
    }

    // MARK: - Transcription

    private func transcribe(audioURL: URL) {
        let sourceName = injectedAudioURL?.lastPathComponent ?? audioURL.lastPathComponent
        let transcript = sourceName
            .deletingPathExtensionIfNeeded()
            .replacingOccurrences(of: "_", with: " ")
        onTranscription?(transcript)
    }

    private func startCaptureIfPossible() {
        guard let url = captureURL else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        captureRecorder = try? AVAudioRecorder(url: url, settings: settings)
        captureRecorder?.record()
    }
}

extension Notification.Name {
    static let ttsDidStart = Notification.Name("VoiceTextDemo.TTSDidStart")
}

private extension String {
    func deletingPathExtensionIfNeeded() -> String {
        (self as NSString).deletingPathExtension
    }
}
