import Foundation
import Combine
import AVFoundation

// MARK: - Models

struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum MessageRole: String, Codable {
    case user, assistant
}

// MARK: - ViewModel

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isThinking: Bool = false
    @Published var isConnected: Bool = false
    @Published var lastToolCalled: String = ""

    private let audioManager = AudioManager()
    private var cancellables = Set<AnyCancellable>()

    // NOTE: In production, load from environment / keychain.
    // For the harness demo this is injected via launch arguments.
    private var apiKey: String {
        ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
            ?? Bundle.main.infoDictionary?["OPENROUTER_API_KEY"] as? String
            ?? ""
    }

    private var apiBaseURL: String {
        ProcessInfo.processInfo.environment["OPENROUTER_BASE_URL"]
            ?? "https://openrouter.ai/api/v1"
    }

    private var modelName: String {
        ProcessInfo.processInfo.environment["OPENROUTER_MODEL"]
            ?? "openrouter/free"
    }

    // Regression flag: set to true to deliberately break tool-call behaviour.
    // Harness sets via launch arg: -REGRESSION_BREAK_TOOL_CALL YES
    private var regressionBreakToolCall: Bool {
        ProcessInfo.processInfo.environment["REGRESSION_BREAK_TOOL_CALL"] == "YES"
    }

    func setup() {
        isConnected = !apiKey.isEmpty
        audioManager.onTranscription = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.messages.append(ChatMessage(role: .user, content: text))
                await self.sendToLLM(userText: text, speakResponse: true)
            }
        }
    }

    func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        Task { await sendToLLM(userText: text, speakResponse: false) }
    }

    func toggleVoice() {
        if isRecording {
            audioManager.stopRecording()
            isRecording = false
        } else {
            audioManager.startRecording()
            isRecording = true
        }
    }

    // MARK: - LLM

    private func sendToLLM(userText: String, speakResponse: Bool) async {
        isThinking = true
        defer { isThinking = false }

        let systemPrompt: String
        if regressionBreakToolCall {
            // Deliberate regression: remove weather tool instruction so agent never calls it.
            systemPrompt = "You are a helpful assistant."
        } else {
            systemPrompt = """
            You are a helpful assistant. When asked about weather, you MUST call the get_weather tool. \
            When asked to book a table, confirm the details clearly. Always be concise.
            """
        }

        var messagesPayload: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        messagesPayload.append(contentsOf: messages.dropLast().map {
            ["role": $0.role.rawValue, "content": $0.content] as [String: Any]
        })
        messagesPayload.append(["role": "user", "content": userText])

        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "get_weather",
                    "description": "Get current weather for a location",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "location": [
                                "type": "string",
                                "description": "City name"
                            ]
                        ],
                        "required": ["location"],
                        "additionalProperties": false
                    ]
                ]
            ]
        ]

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 512,
            "messages": messagesPayload,
            "tools": tools,
            "tool_choice": "auto"
        ]

        guard let url = URL(string: "\(apiBaseURL)/chat/completions"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first,
                  let message = choice["message"] as? [String: Any] else { return }

            var responseText = ""
            var toolCalled: String? = nil

            if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    if let function = call["function"] as? [String: Any],
                       let name = function["name"] as? String {
                        toolCalled = name
                        if name == "get_weather" {
                            let arguments = function["arguments"] as? String ?? "{}"
                            let argumentData = arguments.data(using: .utf8) ?? Data()
                            let decoded = (try? JSONSerialization.jsonObject(with: argumentData) as? [String: Any]) ?? [:]
                            let location = decoded["location"] as? String ?? "unknown"
                            responseText = "The weather in \(location) is currently 28C and sunny."
                        }
                    }
                }
            }

            if responseText.isEmpty, let text = message["content"] as? String {
                responseText = text
            }

            lastToolCalled = toolCalled ?? ""
            if let tool = toolCalled {
                NotificationCenter.default.post(name: .toolCalled, object: nil, userInfo: ["tool": tool])
                UserDefaults.standard.set(tool, forKey: "last_tool_called")
            } else {
                UserDefaults.standard.removeObject(forKey: "last_tool_called")
            }

            if !responseText.isEmpty {
                let assistantMessage = ChatMessage(role: .assistant, content: responseText)
                messages.append(assistantMessage)
                if speakResponse {
                    audioManager.speak(text: responseText)
                }
            }
        } catch {
            messages.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }
    }
}

extension Notification.Name {
    static let toolCalled = Notification.Name("VoiceTextDemo.ToolCalled")
}
