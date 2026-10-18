import Foundation

/// One model's answer plus its on-device performance metrics (from Ollama's own
/// response fields), so the app can compare models side by side.
public struct ModelRun: Identifiable {
    public let id = UUID()
    public let model: String
    public let text: String
    /// Input tokens when the backend exposed them. Nil means unavailable, not zero.
    public let promptTokens: Int?
    /// Output tokens when the backend exposed them. Nil means unavailable, not zero.
    public let outputTokens: Int?
    public let totalSeconds: Double   // total_duration
    public let evalSeconds: Double    // eval_duration (generation only)

    public init(model: String, text: String, promptTokens: Int?, outputTokens: Int?,
                totalSeconds: Double, evalSeconds: Double) {
        self.model = model
        self.text = text
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.totalSeconds = totalSeconds
        self.evalSeconds = evalSeconds
    }

    public var tokensPerSecond: Double {
        guard let outputTokens, evalSeconds > 0 else { return 0 }
        return Double(outputTokens) / evalSeconds
    }
}
