import FoundationModels

/// Apple's availability, collapsed to the distinction the router acts on:
/// can this answer still change?
///
/// Hardware eligibility never changes while the process is alive, so
/// `.unavailablePermanently` is the one answer the router is allowed to
/// remember. Being available, Apple Intelligence being switched off, and a
/// model still downloading are all conditions the user can change from under
/// us, so the router re-reads them every time.
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
}
