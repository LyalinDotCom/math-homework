import Foundation

/// Minimal URLSession client for the Gemini Interactions API, matching the
/// wire behavior the desktop app gets from @google/genai: POST
/// {base}/v1beta/interactions with an x-goog-api-key header, retrying
/// timeouts, 408/429, and 5xx up to three attempts with backoff.
struct GeminiInteractionsClient {
    enum ClientError: LocalizedError {
        case notConfigured
        case api(String)
        case emptyOutput(String)
        case modelMismatch(expected: String, received: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Gemini is not configured. Add your API key in Settings."
            case .api(let message):
                return message
            case .emptyOutput(let label):
                return "Gemini returned no \(label)"
            case .modelMismatch(let expected, let received):
                return "Model mismatch: expected \(expected), received \(received)"
            }
        }
    }

    let apiKey: String
    let model: String

    private static let endpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/interactions"
    )!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    /// Runs one structured OCR interaction and returns the model's JSON text.
    func createStructuredInteraction(
        promptText: String,
        jpegData: Data,
        schema: [String: Any],
        label: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.notConfigured }

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                ["type": "text", "text": promptText],
                [
                    "type": "image",
                    "data": jpegData.base64EncodedString(),
                    "mime_type": "image/jpeg",
                ],
            ],
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": schema,
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = bodyData

        var lastError: Error = ClientError.api("Gemini request failed")
        for attempt in 1...3 {
            do {
                let (data, response) = try await Self.session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    let message = Self.errorMessage(from: data, status: status)
                    if Self.isRetriableStatus(status), attempt < 3 {
                        lastError = ClientError.api(message)
                        try await Self.backoff(attempt: attempt)
                        continue
                    }
                    throw ClientError.api(message)
                }
                return try Self.parseOutputText(data: data, expectedModel: model, label: label)
            } catch let error as ClientError {
                throw error
            } catch {
                lastError = error
                guard attempt < 3, Self.isRetriable(error) else { throw error }
                try await Self.backoff(attempt: attempt)
            }
        }
        throw lastError
    }

    private static func backoff(attempt: Int) async throws {
        let milliseconds = 400 * (1 << (attempt - 1))
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private static func isRetriableStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || status >= 500
    }

    private static func isRetriable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .notConnectedToInternet, .dnsLookupFailed, .cancelled:
            return true
        default:
            return false
        }
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        // Errors arrive either as {"error": {...}} or wrapped in an array.
        let object = try? JSONSerialization.jsonObject(with: data)
        let dictionary =
            (object as? [String: Any])
            ?? (object as? [[String: Any]])?.first
        if let error = dictionary?["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "Gemini request failed with status \(status)"
    }

    private struct InteractionResponse: Decodable {
        struct Step: Decodable {
            struct Content: Decodable {
                let type: String?
                let text: String?
            }

            let type: String?
            let content: [Content]?
        }

        let model: String?
        let steps: [Step]?
    }

    private static func parseOutputText(
        data: Data,
        expectedModel: String,
        label: String
    ) throws -> String {
        let interaction = try JSONDecoder().decode(InteractionResponse.self, from: data)
        if let received = interaction.model, received != expectedModel {
            throw ClientError.modelMismatch(expected: expectedModel, received: received)
        }
        // Same as the SDK's output_text: walk steps from the end, collecting
        // text out of trailing model_output steps.
        var textParts: [String] = []
        var collecting = false
        outer: for step in (interaction.steps ?? []).reversed() {
            if step.type == "user_input" { break }
            guard step.type == "model_output", let content = step.content else {
                if collecting { break }
                continue
            }
            for item in content.reversed() {
                if item.type == "text" {
                    collecting = true
                    textParts.append(item.text ?? "")
                } else if collecting {
                    break outer
                }
            }
        }
        let outputText = textParts.reversed().joined()
        guard !outputText.isEmpty else { throw ClientError.emptyOutput(label) }
        return outputText
    }
}
