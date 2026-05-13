import Foundation
import XCTest

/// AudioBridgeTests drives the sample app through UI interactions and
/// writes a small JSON payload for the Python harness to verify.
final class AudioBridgeTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment["OPENROUTER_API_KEY"] = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        app.launchEnvironment["OPENROUTER_BASE_URL"] = ProcessInfo.processInfo.environment["OPENROUTER_BASE_URL"] ?? "https://openrouter.ai/api/v1"
        app.launchEnvironment["OPENROUTER_MODEL"] = ProcessInfo.processInfo.environment["OPENROUTER_MODEL"] ?? "openrouter/free"
        if let inputAudio = ProcessInfo.processInfo.environment["CASE_INPUT_AUDIO"], !inputAudio.isEmpty {
            app.launchEnvironment["CASE_INPUT_AUDIO"] = inputAudio
        }

        if let breakFlag = ProcessInfo.processInfo.environment["REGRESSION_BREAK_TOOL_CALL"] {
            app.launchEnvironment["REGRESSION_BREAK_TOOL_CALL"] = breakFlag
        }
        app.launch()
    }

    /// Entry point called by the Python runner for every test case.
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

        let assistantMessage = latestAssistantMessage()
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 30), "Assistant did not respond within 30s")

        writeOutput(
            outputPath: outputPath,
            payload: [
                "type": "text",
                "response_text": assistantMessage.label,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    // MARK: - Voice case

    private func runVoiceCase(outputPath: String) throws {
        let voiceButton = app.buttons["voice_button"]
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 10))

        voiceButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        voiceButton.tap()

        let assistantMessage = latestAssistantMessage()
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 30), "Assistant did not respond to voice input")
        let capturedAudioPath = app.staticTexts["captured_audio_path"].exists ? app.staticTexts["captured_audio_path"].label : ""

        writeOutput(
            outputPath: outputPath,
            payload: [
                "type": "voice",
                "response_text": assistantMessage.label,
                "captured_audio_path": capturedAudioPath,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    // MARK: - Helpers

    private func latestAssistantMessage() -> XCUIElement {
        let messages = app.staticTexts.matching(identifier: "assistant_message")
        return messages.lastMatch
    }

    private func writeOutput(outputPath: String, payload: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        try! data.write(to: URL(fileURLWithPath: outputPath + ".json"))
    }
}
