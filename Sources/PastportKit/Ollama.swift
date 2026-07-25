import Foundation

/// One model's answer plus its on-device performance metrics (from Ollama's own
/// response fields), so the app can compare models side by side.
public struct ModelRun: Identifiable {
    public let id = UUID()
    public let model: String
    public let text: String
    public let promptTokens: Int      // prompt_eval_count (input)
    public let outputTokens: Int      // eval_count (output)
    public let totalSeconds: Double   // total_duration
    public let evalSeconds: Double    // eval_duration (generation only)

    public var tokensPerSecond: Double {
        evalSeconds > 0 ? Double(outputTokens) / evalSeconds : 0
    }
}

/// Minimal async client for a local Ollama server (default http://localhost:11434).
/// Everything stays on-device; nothing is sent to any cloud provider.
public enum Ollama {
    private static let base = "http://localhost:11434"

    /// Names of all locally installed models (GET /api/tags).
    public static func listModels() async throws -> [String] {
        guard let url = URL(string: "\(base)/api/tags") else { throw CLIError.msg("bad Ollama URL") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let data = try await fetch(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else {
            throw CLIError.msg("unexpected /api/tags response from Ollama")
        }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// Run a prompt and return the text only (used by the CLI).
    public static func generate(model: String, prompt: String) async throws -> String {
        try await run(model: model, prompt: prompt).text
    }

    /// Multi-turn chat (/api/chat) — messages are [["role": "system|user|assistant", "content": ...]].
    public static func chat(model: String, messages: [[String: String]]) async throws -> String {
        guard let url = URL(string: "\(base)/api/chat") else { throw CLIError.msg("bad Ollama URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": model, "messages": messages, "stream": false]
        )
        let data = try await fetch(request, model: model)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CLIError.msg("unexpected /api/chat response from Ollama")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run a prompt and return the text plus performance metrics (used by the app).
    public static func run(model: String, prompt: String) async throws -> ModelRun {
        guard let url = URL(string: "\(base)/api/generate") else { throw CLIError.msg("bad Ollama URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": model, "prompt": prompt, "stream": false]
        )

        let data = try await fetch(request, model: model)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.msg("unexpected response from Ollama")
        }
        if let text = o["response"] as? String {
            func ns(_ key: String) -> Double { ((o[key] as? NSNumber)?.doubleValue ?? 0) / 1e9 }
            func int(_ key: String) -> Int { (o[key] as? NSNumber)?.intValue ?? 0 }
            return ModelRun(
                model: model,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                promptTokens: int("prompt_eval_count"),
                outputTokens: int("eval_count"),
                totalSeconds: ns("total_duration"),
                evalSeconds: ns("eval_duration")
            )
        }
        if let message = o["error"] as? String { throw CLIError.msg("Ollama error: \(message)") }
        throw CLIError.msg("no `response` field from Ollama")
    }

    /// Perform a request with friendly error messages for the common failures.
    private static func fetch(_ request: URLRequest, model: String? = nil) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw CLIError.msg("Ollama returned 404 — is the model pulled?"
                    + (model.map { " Try `ollama pull \($0)`." } ?? ""))
            }
            return data
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError.msg(
                "Could not reach Ollama at localhost:11434 (\(error.localizedDescription)). "
                + "Is it running? Try `ollama serve`."
            )
        }
    }
}
