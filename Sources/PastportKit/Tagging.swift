import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Guided generation over intent threads.
///
/// Two things are deliberate here.
///
/// **The output shape is the guardrail, not the prompt.** `brief` used to narrate a bare
/// coordinate as free prose and the model called one city "the bustling city of another" —
/// there is no geocoder anywhere in this package, so it simply invented one. Asking a 3B
/// model more nicely does not fix that. Removing the field it can put a city *in* does:
/// `ThreadNarration` has nowhere to write a place name.
///
/// **One session per thread.** The on-device context window is 4096 tokens *per
/// `LanguageModelSession`* (TN3193), so a fresh session per thread is a fresh budget —
/// rather than one session that has to be capped at 60 rows to fit.

/// A narrated thread. Plain and always available, so callers don't inherit an
/// availability annotation from the framework-gated type it's generated from.
public struct ThreadNarration {
    public let intent: String
    public let exposure: String

    public init(intent: String, exposure: String) {
        self.intent = intent
        self.exposure = exposure
    }
}

public enum Guided {

    /// Narrate one thread into a fixed shape. Returns nil rather than throwing when the
    /// model declines — a refusal on one thread shouldn't sink a whole monthly brief.
    public static func narrate(_ thread: IntentThread,
                               instruction: String? = nil) async throws -> ThreadNarration? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(instructions: """
                You read a person's own browsing, on device, for that person. Be plain and \
                specific. Never judge them. Never name a place, company, or product that is \
                not written verbatim in the input.
                """)
            session.prewarm()
            do {
                let response = try await session.respond(
                    to: Threads.narrationPrompt(for: thread, instruction: instruction),
                    generating: GeneratedNarration.self
                )
                return ThreadNarration(intent: response.content.intent,
                                       exposure: response.content.exposure)
            } catch let error as LanguageModelSession.GenerationError {
                // Guardrails block sensitive input as well as output, so some of a real
                // history simply cannot be narrated by this backend. Skip, don't fail.
                if case .guardrailViolation = error { return nil }
                throw CLIError.msg("\(error)")
            }
        }
        #endif
        throw CLIError.msg("Guided narration needs macOS 26 with Apple Intelligence enabled.")
    }

}

#if canImport(FoundationModels)

/// The generated shape. Note what is absent: there is no `place`, `city`, or `country`
/// field, so constrained sampling gives the model nowhere to invent one.
@available(macOS 26, *)
@Generable
struct GeneratedNarration {
    @Guide(description: "One sentence: what the person was trying to work out.")
    var intent: String

    @Guide(description: "One sentence: what this reveals was recorded about them.")
    var exposure: String
}

#endif
