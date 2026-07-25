import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device Foundation model as an analysis backend, so it can be compared
/// against local Ollama models. Requires macOS 26 + Apple Intelligence enabled;
/// everything stays on device.
public enum AppleFoundation {
    public static let displayName = "Apple Foundation"

    /// True when the framework is present and the OS is new enough. Actual
    /// readiness (Apple Intelligence enabled, model downloaded) surfaces at run time.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    /// Run a prompt on the on-device Apple model. Timing is measured locally
    /// (the framework doesn't expose token counts, so those are reported as 0).
    public static func run(prompt: String) async throws -> ModelRun {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let start = Date()
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let elapsed = Date().timeIntervalSince(start)
            return ModelRun(
                model: displayName,
                text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
                promptTokens: 0,
                outputTokens: 0,
                totalSeconds: elapsed,
                evalSeconds: elapsed
            )
        }
        #endif
        throw CLIError.msg("Apple Foundation Models needs macOS 26 with Apple Intelligence enabled.")
    }

    public static func generate(prompt: String) async throws -> String {
        try await run(prompt: prompt).text
    }
}
