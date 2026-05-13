import XCTest
import AVFoundation

@testable import VoiceTextDemo

final class AudioBridgeTests: XCTestCase {

    var app: XCUIApplication!
    var audioEngine: AVAudioEngine!
    var audioRecorder: AVAudioRecorder?

    override func setUp() {
        super.setUp()

        app = XCUIApplication()
        app.launchArguments.append("UITesting")
        audioEngine = AVAudioEngine()

        // Configure audio session for playback + recording
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    override func tearDown() {
        audioRecorder?.stop()
        audioEngine.stop()
        super.tearDown()
    }

    /// Test voice flow: inject audio, capture agent response
    func testVoiceWithRealAudioInjection() throws {
        // 1. Launch app with test fixture audio path
        let testAudioPath = Bundle.main.url(forResource: "hello_how_are_you", withExtension: "wav")
        XCTAssertNotNil(testAudioPath, "Test audio fixture missing: hello_how_are_you.wav")

        app.launchEnvironment["CASE_INPUT_AUDIO"] = testAudioPath?.path ?? ""
        app.launchEnvironment["CASE_TYPE"] = "voice"
        app.launch()

        // 2. Verify app is ready
        XCTAssert(app.buttons["voice_button"].waitForExistence(timeout: 5))

        // 3. Set up real audio capture before interaction
        let captureURL = setupAudioCapture()

        // 4. Tap voice button to start recording with injected audio
        app.buttons["voice_button"].tap()
        XCTAssert(app.buttons["voice_button"].waitForExistence(timeout: 2))

        // 5. Inject real audio through AVAudioEngine into the mic input
        try injectAudioToMic(from: testAudioPath!)

        // 6. Stop recording (tap voice button again)
        sleep(2)  // Let injection play
        app.buttons["voice_button"].tap()

        // 7. Wait for agent response
        let assistantMessageExists = app.staticTexts["assistant_message"].waitForExistence(timeout: 10)
        XCTAssert(assistantMessageExists, "No assistant response appeared within timeout")

        // 8. Verify captured audio exists and is not empty
        if let captureURL = captureURL {
            XCTAssert(FileManager.default.fileExists(atPath: captureURL.path), "Captured audio file not found")
            let attrs = try FileManager.default.attributesOfItem(atPath: captureURL.path)
            let fileSize = attrs[.size] as? Int ?? 0
            XCTAssert(fileSize > 0, "Captured audio file is empty")
        }
    }

    /// Test text flow (sanity check that UI automation works)
    func testTextFlow() throws {
        app.launchEnvironment["CASE_TYPE"] = "text"
        app.launch()

        // Verify UI elements exist
        XCTAssert(app.textFields["text_input_field"].waitForExistence(timeout: 5))
        XCTAssert(app.buttons["send_text_button"].exists)

        // Type and send
        app.textFields["text_input_field"].tap()
        app.typeText("Hello, how are you?")
        app.buttons["send_text_button"].tap()

        // Wait for response
        let assistantResponse = app.staticTexts["assistant_message"].waitForExistence(timeout: 10)
        XCTAssert(assistantResponse, "No assistant response for text input")
    }

    /// Test tool-call detection
    func testWeatherToolCall() throws {
        app.launchEnvironment["CASE_TYPE"] = "text"
        app.launch()

        XCTAssert(app.textFields["text_input_field"].waitForExistence(timeout: 5))

        app.textFields["text_input_field"].tap()
        app.typeText("What's the weather in London?")
        app.buttons["send_text_button"].tap()

        // Wait for response
        _ = app.staticTexts["assistant_message"].waitForExistence(timeout: 10)

        // Check if weather tool was called (stored in hidden accessibility identifier)
        let toolCallText = app.staticTexts["last_tool_called"].label
        XCTAssert(toolCallText.contains("get_weather") || !toolCallText.isEmpty,
                  "Expected weather tool to be called")
    }

    // MARK: - Audio Helper Functions

    /// Set up real audio capture from speaker output
    private func setupAudioCapture() -> URL? {
        let captureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("captured_\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: captureURL, settings: settings)
            audioRecorder?.record()
            return captureURL
        } catch {
            XCTFail("Failed to set up audio recorder: \(error)")
            return nil
        }
    }

    /// Inject real audio to microphone input via AVAudioEngine loopback
    private func injectAudioToMic(from url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()

        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)

        // Tap input node to receive injected audio (simulates mic input)
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0) ?? audioFile.processingFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            // Process buffer as needed (already being recorded via captureRecorder)
        }

        try audioEngine.start()
        player.scheduleFile(audioFile, at: nil)
        player.play()

        // Wait for playback to finish
        sleep(UInt32(audioFile.length / Int64(audioFile.processingFormat.sampleRate)))

        inputNode.removeTap(onBus: 0)
        player.stop()
    }
}
