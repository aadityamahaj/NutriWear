import Foundation

/// Model IDs in one place so they're easy to swap if Groq rotates them.
enum GroqModel {
    /// Multimodal vision model for food recognition (Qwen3 is vision-capable).
    static let vision = "qwen/qwen3.8-27b"
    /// Fast text model for coaching + voice answers.
    static let text = "openai/gpt-oss-120b"
}

enum GroqError: LocalizedError {
    case missingKey
    case badResponse(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Groq API key configured. Add one in Secrets.xcconfig."
        case .badResponse(let code, let body):
            return "Groq API error (\(code)): \(body)"
        case .decoding(let detail):
            return "Couldn't read the AI response: \(detail)"
        case .transport(let detail):
            return "Network problem reaching Groq: \(detail)"
        }
    }
}

/// A message in an OpenAI-compatible chat request. Content can be plain text
/// or a multimodal array (text + image) for vision calls.
struct ChatMessage {
    enum Content {
        case text(String)
        /// text prompt plus a base64 JPEG data URL
        case textWithImage(text: String, imageDataURL: String)
    }

    let role: String   // "system" | "user" | "assistant"
    let content: Content

    static func system(_ text: String) -> ChatMessage { .init(role: "system", content: .text(text)) }
    static func user(_ text: String) -> ChatMessage { .init(role: "user", content: .text(text)) }
    static func assistant(_ text: String) -> ChatMessage { .init(role: "assistant", content: .text(text)) }
    static func userImage(prompt: String, imageDataURL: String) -> ChatMessage {
        .init(role: "user", content: .textWithImage(text: prompt, imageDataURL: imageDataURL))
    }
}

/// Minimal Groq (OpenAI-compatible) chat client.
actor GroqClient {
    static let shared = GroqClient()

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    /// Reads the key injected from Secrets.xcconfig via Info.plist.
    static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "gsk_your_key_here" { return nil }
        return trimmed
    }

    static var isConfigured: Bool { apiKey != nil }

    /// Sends a chat completion request and returns the assistant's text content.
    /// - Parameters:
    ///   - jsonMode: ask the model to return strict JSON (used for food recognition).
    func complete(
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.4,
        maxTokens: Int = 1200,
        jsonMode: Bool = false
    ) async throws -> String {
        guard let key = GroqClient.apiKey else { throw GroqError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": messages.map(Self.encodeMessage)
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GroqError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GroqError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GroqError.badResponse(http.statusCode, String(bodyText.prefix(500)))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw GroqError.decoding("Unexpected response shape")
        }

        return content
    }

    private static func encodeMessage(_ message: ChatMessage) -> [String: Any] {
        switch message.content {
        case .text(let text):
            return ["role": message.role, "content": text]
        case .textWithImage(let text, let imageDataURL):
            return [
                "role": message.role,
                "content": [
                    ["type": "text", "text": text],
                    ["type": "image_url", "image_url": ["url": imageDataURL]]
                ]
            ]
        }
    }
}
