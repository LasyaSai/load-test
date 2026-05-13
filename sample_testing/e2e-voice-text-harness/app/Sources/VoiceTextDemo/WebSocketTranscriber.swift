import Foundation

class WebSocketTranscriber {
    private var webSocketTask: URLSessionWebSocketTask?
    private let wsURL: URL
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    init(wsURL: URL) {
        self.wsURL = wsURL
    }

    func transcribeAudio(_ audioData: Data, filename: String, completion: @escaping (Result<String, Error>) -> Void) {
        let payload: [String: Any] = [
            "audio": audioData.base64EncodedString(),
            "filename": filename
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(NSError(domain: "WebSocketTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode payload"])))
            return
        }

        connect { [weak self] result in
            switch result {
            case .success:
                self?.sendMessage(jsonData, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        if webSocketTask?.state == .running {
            completion(.success(()))
            return
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        // Brief delay to ensure connection is established
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion(.success(()))
        }
    }

    private func sendMessage(_ jsonData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let webSocketTask = webSocketTask, webSocketTask.state == .running else {
            completion(.failure(NSError(domain: "WebSocketTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"])))
            return
        }

        let message = URLSessionWebSocketTask.Message.data(jsonData)
        webSocketTask.send(message) { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }
            self?.receiveMessage(completion: completion)
        }
    }

    private func receiveMessage(completion: @escaping (Result<String, Error>) -> Void) {
        guard let webSocketTask = webSocketTask else {
            completion(.failure(NSError(domain: "WebSocketTranscriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebSocket task lost"])))
            return
        }

        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self?.parseTranscriptResponse(data, completion: completion)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self?.parseTranscriptResponse(data, completion: completion)
                    } else {
                        completion(.failure(NSError(domain: "WebSocketTranscriber", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                @unknown default:
                    completion(.failure(NSError(domain: "WebSocketTranscriber", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unknown message type"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseTranscriptResponse(_ data: Data, completion: @escaping (Result<String, Error>) -> Void) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "WebSocketTranscriber", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
            }

            if let transcript = json["transcript"] as? String {
                completion(.success(transcript))
            } else if let error = json["error"] as? String {
                throw NSError(domain: "WebSocketTranscriber", code: 7, userInfo: [NSLocalizedDescriptionKey: "Backend error: \(error)"])
            } else {
                throw NSError(domain: "WebSocketTranscriber", code: 8, userInfo: [NSLocalizedDescriptionKey: "No transcript in response"])
            }
        } catch {
            completion(.failure(error))
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    deinit {
        disconnect()
    }
}
