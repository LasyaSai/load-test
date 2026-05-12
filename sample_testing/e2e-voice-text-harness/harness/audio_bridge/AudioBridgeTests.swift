import XCTest
import AVFoundation

/// AudioBridgeTests provides the real audio injection and capture layer.
/// Called by the Python runner via `xcodebuild test -only-testing:AudioBridgeTests/AudioBridgeTests/runCase`
/// with environment variables set per test case.
class AudioBridgeTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment["OPENROUTER_API_KEY"] = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        app.launchEnvironment["OPENROUTER_BASE_URL"] = ProcessInfo.processInfo.environment["OPENROUTER_BASE_URL"] ?? "https://openrouter.ai/api/v1"
        app.launchEnvironment["OPENROUTER_MODEL"] = ProcessInfo.processInfo.environment["OPENROUTER_MODEL"] ?? "openrouter/free"

        // Regression break flag forwarded from runner
        if let breakFlag = ProcessInfo.processInfo.environment["REGRESSION_BREAK_TOOL_CALL"] {
            app.launchEnvironment["REGRESSION_BREAK_TOOL_CALL"] = breakFlag
        }
        app.launch()
    }

    /// Entry point called by the Python runner for every test case.
    /// Reads case config from env vars:
    ///   CASE_TYPE        = "voice" | "text"
    ///   CASE_INPUT_TEXT  = text to type (text cases)
    ///   CASE_INPUT_AUDIO = absolute path to WAV file (voice cases)
    ///   CASE_OUTPUT_PATH = path to write captured audio / response text
    func testRunCase() throws {
        let caseType = ProcessInfo.processInfo.environment["CASE_TYPE"] ?? "text"
        let outputPath = ProcessInfo.processInfo.environment["CASE_OUTPUT_PATH"] ?? "/tmp/case_output"

        switch caseType {
        case "voice":
            try runVoiceCase(outputPath: outputPath)
        default:
        
            try runTextCase(outputPath: outputPath)
        }
    }

    // MARK: - Text case

    private func runTextCase(outputPath: String) throws {
        let inputText = ProcessInfo.processInfo.environment["CASE_INPUT_TEXT"] ?? ""

        let textField = app.textFields["text_input_field"]
        XCTAssertTrue(textField.waitForExistence(timeout: 10))
        textField.tap()
        textField.typeText(inputText)
        app.buttons["send_text_button"].tap()

        // Wait for assistant response
        let assistantMessage = app.staticTexts.matching(identifier: "assistant_message").firstMatch
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 30), "Assistant did not respond within 30s")

        // Capture last assistant message text
        let responseText = assistantMessage.label
        let toolLabel = app.staticTexts["last_tool_called"]
        let toolCalled = toolLabel.exists ? toolLabel.label : ""

        // Write output for verifier
        var output: [String: Any] = [
            "type": "text",
            "response_text": responseText,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if !toolCalled.isEmpty {
            output["tool_called"] = toolCalled
        }

        let data = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: outputPath + ".json"))
    }

    // MARK: - Voice case

    private func runVoiceCase(outputPath: String) throws {
        let inputAudioPath = ProcessInfo.processInfo.environment["CASE_INPUT_AUDIO"] ?? ""
        let inputURL = URL(fileURLWithPath: inputAudioPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputAudioPath), "Fixture not found: \(inputAudioPath)")

        // Start capturing speaker output before triggering voice
        let captureURL = URL(fileURLWithPath: outputPath + "_captured.wav")
        let captureRecorder = try startCapture(to: captureURL)

        // Inject audio via AVAudioEngine player node into the simulator's virtual mic
        let injectionDone = expectation(description: "Audio injection complete")
        injectAudio(from: inputURL) { injectionDone.fulfill() }
        wait(for: [injectionDone], timeout: 30)

        // Wait for agent TTS to start and finish
        let ttsStarted = expectation(description: "TTS started")
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("VoiceTextDemo.TTSDidStart"),
            object: nil, queue: .main
        ) { _ in ttsStarted.fulfill() }
        wait(for: [ttsStarted], timeout: 30)
        NotificationCenter.default.removeObserver(observer)

        // Allow TTS to finish (estimate based on average speech rate)
        Thread.sleep(forTimeInterval: 5.0)
        captureRecorder.stop()

        // Read last assistant message text as backup
        let assistantMessage = app.staticTexts.matching(identifier: "assistant_message").firstMatch
        let responseText = assistantMessage.exists ? assistantMessage.label : ""
        let toolLabel = app.staticTexts["last_tool_called"]
        let toolCalled = toolLabel.exists ? toolLabel.label : ""

        var output: [String: Any] = [
            "type": "voice",
            "response_text": responseText,
            "captured_audio_path": captureURL.path,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if !toolCalled.isEmpty {
            output["tool_called"] = toolCalled
        }

        let data = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: outputPath + ".json"))
    }

    // MARK: - Audio helpers

    /// Injects a WAV file into the simulator mic via AVAudioEngine player node.
    /// On the simulator, the audio HAL routes player output through the input bus.
    private func injectAudio(from url: URL, completion: @escaping () -> Void) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let file = try? AVAudioFile(forReading: url) else { completion(); return }
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        player.scheduleFile(file, at: nil) { completion() }
        try? engine.start()
        player.play()

        // Keep engine alive in this scope until completion fires
        objc_setAssociatedObject(self, &AssociatedKeys.engine, engine, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Records from the default output (speaker) bus to a WAV file.
    private func startCapture(to url: URL) throws -> AVAudioRecorder {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()
        return recorder
    }
}

private enum AssociatedKeys {
    static var engine = "engine"
}
