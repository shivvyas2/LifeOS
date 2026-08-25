import FoundationModels

/// What to do when the on-device model fails.
public enum Disposition: Sendable, Equatable {
    /// The cloud can serve this; the on-device model cannot.
    case escalate
    /// Our fault, and transient. Try again here.
    case retryLocally
    /// One more local attempt, then the cloud.
    case retryThenEscalate
    /// Show the user. Do not route around it.
    case surface
    /// Our fault, and permanent. Fail loudly.
    case programmerError
}

/// The escalation table from the design spec, as a pure function.
///
/// Kept separate from the router precisely so that every branch can be
/// exercised without a model, a network, or a container.
public enum EscalationPolicy {

    public static func disposition(
        for error: LanguageModelSession.GenerationError
    ) -> Disposition {
        switch error {
        case .exceededContextWindowSize:
            // The expected trigger. The cloud has room; we do not.
            return .escalate

        case .assetsUnavailable, .rateLimited, .unsupportedLanguageOrLocale:
            return .escalate

        case .decodingFailure:
            // A small model losing a schema is often a one-off. Spend a free
            // retry before spending money.
            return .retryThenEscalate

        case .concurrentRequests:
            // The router is supposed to serialise. This is our bug, and
            // billing a cloud call for it would hide that.
            return .retryLocally

        case .unsupportedGuide:
            // A @Guide the model cannot honour is a static property of our
            // own schema. It will fail identically on every request forever.
            return .programmerError

        case .refusal, .guardrailViolation:
            // Never escalate. Re-routing a refused request to another
            // provider to obtain the answer anyway is guardrail laundering.
            return .surface

        @unknown default:
            // A case Apple added after this was written. Surfacing is the
            // conservative choice: it cannot spend money and cannot hide a
            // safety decision.
            return .surface
        }
    }
}
