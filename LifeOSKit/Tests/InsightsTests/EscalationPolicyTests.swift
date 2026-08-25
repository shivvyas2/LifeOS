import Testing
import FoundationModels
@testable import Insights

@Suite struct EscalationPolicyTests {

    private let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    @Test func runningOutOfContextEscalates() {
        #expect(EscalationPolicy.disposition(for: .exceededContextWindowSize(context)) == .escalate)
    }

    @Test func missingModelAssetsEscalate() {
        #expect(EscalationPolicy.disposition(for: .assetsUnavailable(context)) == .escalate)
    }

    @Test func aSystemThrottleEscalatesRatherThanWaits() {
        #expect(EscalationPolicy.disposition(for: .rateLimited(context)) == .escalate)
    }

    @Test func anUnsupportedLocaleEscalates() {
        #expect(EscalationPolicy.disposition(for: .unsupportedLanguageOrLocale(context)) == .escalate)
    }

    @Test func aLostSchemaIsRetriedBeforeItCostsMoney() {
        #expect(EscalationPolicy.disposition(for: .decodingFailure(context)) == .retryThenEscalate)
    }

    /// Concurrent requests are our own bug: the router is supposed to
    /// serialise. Escalating would mean paying money for a race condition.
    @Test func ourOwnConcurrencyBugIsRetriedLocallyAndNeverBilled() {
        #expect(EscalationPolicy.disposition(for: .concurrentRequests(context)) == .retryLocally)
    }

    /// A guide the model cannot honour is a static property of our schema.
    /// Escalating would hide a bug we would never otherwise find.
    @Test func anImpossibleGuideIsOurBugAndMustNotBeHidden() {
        #expect(EscalationPolicy.disposition(for: .unsupportedGuide(context)) == .programmerError)
    }

    /// The important one. Re-routing a refused request to a different
    /// provider to get the answer anyway is guardrail laundering, and in a
    /// health app the refusals cluster exactly where that is worst.
    @Test func aRefusalIsSurfacedAndNeverEscalated() {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        #expect(EscalationPolicy.disposition(for: .refusal(refusal, context)) == .surface)
    }

    @Test func aGuardrailViolationIsSurfacedAndNeverEscalated() {
        #expect(EscalationPolicy.disposition(for: .guardrailViolation(context)) == .surface)
    }
}
