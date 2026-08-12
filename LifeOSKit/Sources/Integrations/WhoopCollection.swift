import Foundation

/// Every Whoop collection the app reads, with the path it lives at and the
/// OAuth scope Whoop requires to read it.
///
/// These two facts are together in one place because keeping them apart broke
/// the app. `/v2/activity/workout` and `/v2/user/measurement/body` were added
/// to the client while `WhoopOAuth.defaultScopes` still listed only the
/// original three, so Whoop rejected both calls on a token it had just issued.
/// The sync read that 401 as a dead token, deleted the credential the user had
/// granted seconds earlier, and asked them to reconnect, which failed the same
/// way every time.
///
/// Adding a case now forces both halves to be supplied, and `defaultScopes` is
/// derived rather than maintained, so the two cannot drift again.
public enum WhoopCollection: String, CaseIterable, Sendable {
    case recovery
    case sleep
    case cycle
    case workout
    case body

    /// Path relative to the v2 API base.
    public var path: String {
        switch self {
        case .recovery: "recovery"
        case .sleep:    "activity/sleep"
        case .cycle:    "cycle"
        case .workout:  "activity/workout"
        case .body:     "user/measurement/body"
        }
    }

    /// The scope Whoop's documentation lists for this collection. `cycle` is
    /// plural in the scope name and singular in the path; that asymmetry is
    /// Whoop's, not ours.
    public var scope: String {
        switch self {
        case .recovery: "read:recovery"
        case .sleep:    "read:sleep"
        case .cycle:    "read:cycles"
        case .workout:  "read:workout"
        case .body:     "read:body_measurement"
        }
    }
}
