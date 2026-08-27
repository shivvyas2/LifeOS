import Foundation

/// Which engine answers, when both could.
///
/// A preference, not a capability. The floor a task declares still wins: a
/// task that cannot run on the device is not made to by choosing the device,
/// it simply goes where it can run.
public enum TierPreference: String, CaseIterable, Sendable, Identifiable {
    /// Cloud first, device when the cloud cannot answer. The default, and the
    /// only option that has a fallback.
    case automatic
    /// The cloud, and nothing else. Chosen deliberately, so a failure is
    /// reported rather than quietly answered by a weaker model: someone who
    /// picked this wants to know when it did not happen.
    case cloud
    /// The device, and nothing else. Answers are weaker and nothing leaves the
    /// phone, which for some people is the entire point.
    case onDevice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .cloud:     "Cloud"
        case .onDevice:  "On device"
        }
    }

    /// Written in terms of the trade, since that is the choice being made.
    public var detail: String {
        switch self {
        case .automatic: "Best answer available, falling back to the phone when the cloud cannot answer"
        case .cloud:     "Always the stronger model. Needs a connection and uses your daily allowance"
        case .onDevice:  "Answers on the phone. Weaker, and nothing you ask ever leaves it"
        }
    }

    public static let storageKey = "coachTierPreference"
}
