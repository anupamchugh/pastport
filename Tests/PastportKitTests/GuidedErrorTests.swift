import FoundationModels
import Testing
@testable import PastportKit

@Suite("Guided narration errors")
struct GuidedErrorTests {
    private struct Other: Error {}

    @Test("a guardrail violation is a refusal, other errors are not")
    func onlyGuardrailViolationsAreRefusals() {
        #expect(Guided.isGuardrailRefusal(LanguageModelError.guardrailViolation(.init(debugDescription: "test"))))
        #expect(!Guided.isGuardrailRefusal(LanguageModelError.timeout(.init(debugDescription: "test"))))
        #expect(!Guided.isGuardrailRefusal(Other()))
    }
}
