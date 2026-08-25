import FoundationModels

/// Apple's availability, collapsed to the distinction the router acts on:
/// is it worth asking again?
///
/// Hardware eligibility never changes while the process is alive. Apple
/// Intelligence being switched off, or a model still downloading, both do.
/// Asking the framework on every request wastes work on the first and gives
/// a stale answer on the others, so the router caches by this distinction.
public enum ModelAvailability: Sendable, Equatable {
    case available
    case unavailablePermanently
    case unavailableForNow

    public static func from(_ availability: SystemLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailablePermanently
            case .appleIntelligenceNotEnabled, .modelNotReady:
                return .unavailableForNow
            @unknown default:
                // Unknown reasons are assumed transient: re-checking costs a
                // property read, while wrongly caching "never" would disable
                // the free tier for the life of the process.
                return .unavailableForNow
            }
        }
    }

    public var isWorthReChecking: Bool {
        self == .unavailableForNow
    }
}
