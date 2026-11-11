import Foundation
import FoundationModels

/// Apple's on-device Foundation model as an analysis backend, so it can be compared
/// against local Ollama models. Requires macOS 26 + Apple Intelligence enabled;
/// everything stays on device.
public enum AppleFoundation {
    public static let displayName = "Apple Foundation"

    /// True when the framework is present and the OS is new enough. Actual
    /// readiness (Apple Intelligence enabled, model downloaded) surfaces at run time.
    public static var isAvailable: Bool {
        true
    }

    /// True only when Apple Intelligence is enabled and its model is ready on this device.
    public static var isReady: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Run a prompt on the on-device Apple model. Timing is measured locally.
    /// Token counts are copied only when the response exposes them.
    public static func run(prompt: String) async throws -> ModelRun {
        let start = Date()
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(start)
        let usage = foundationTokenUsage(from: response)
        return ModelRun(
            model: displayName,
            text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: usage.input,
            outputTokens: usage.output,
            totalSeconds: elapsed,
            evalSeconds: elapsed
        )
    }

    public static func generate(prompt: String) async throws -> String {
        try await run(prompt: prompt).text
    }
}

/// Token counts from one Foundation Models response. `.unavailable` is the
/// absence of a count. It is never stored as zero.
public enum FoundationTokenUsage: Equatable, Sendable {
    case available(input: Int, output: Int)
    case unavailable

    public var input: Int? {
        guard case .available(let input, _) = self else { return nil }
        return input
    }

    public var output: Int? {
        guard case .available(_, let output) = self else { return nil }
        return output
    }
}

public enum FoundationUsageAccounting {
    /// Both counts must be present. A missing side is unavailable, not zero.
    public static func usage(input: Int?, output: Int?) -> FoundationTokenUsage {
        guard let input, let output else { return .unavailable }
        return .available(input: input, output: output)
    }
}

func foundationTokenUsage<Content: Generable>(
    from response: LanguageModelSession.Response<Content>
) -> FoundationTokenUsage {
    // Runtime availability alone cannot make a newer SDK member compile with
    // an older Xcode. Swift 6.4 ships with the SDK that exposes response usage.
    #if compiler(>=6.4)
    return FoundationUsageAccounting.usage(
        input: response.usage.input.totalTokenCount,
        output: response.usage.output.totalTokenCount
    )
    #else
    return FoundationUsageAccounting.usage(input: nil, output: nil)
    #endif
}
