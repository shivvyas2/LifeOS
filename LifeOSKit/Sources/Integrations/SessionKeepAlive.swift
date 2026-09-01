import Foundation

/// When to renew a session that has not lapsed yet.
///
/// `SessionRefresher` answers "is this session still good", and the app asked
/// it at launch and on every return to the foreground. Both are the wrong
/// moment for the case that actually bites: an access token lives an hour, and
/// somebody who simply keeps the app open passes that hour without either
/// event firing. Every authenticated request then fails with `JWT expired` —
/// friends would not load, the coach could not reach the cloud, notes stopped
/// syncing — and nothing in the app was watching the clock.
///
/// Pure, so the schedule can be tested without waiting an hour for it.
public enum SessionKeepAlive {
    /// How far ahead of expiry the renewal is scheduled.
    ///
    /// Deliberately inside `AuthSession.isExpired`'s own minute of slack.
    /// Waking earlier than that finds a session the refresher considers
    /// healthy, does nothing, and spends the wake for nothing.
    public static let margin: TimeInterval = 45

    /// The shortest the loop will ever wait.
    ///
    /// A session that arrives already expired, or a clock that jumps
    /// backwards, would otherwise compute a delay of zero or less and turn
    /// this into a spin against the auth endpoint.
    public static let floor: TimeInterval = 5

    /// How long to wait before renewing a session that expires at `expiresAt`.
    public static func delay(untilExpiry expiresAt: Date, now: Date = .now) -> TimeInterval {
        max(expiresAt.timeIntervalSince(now) - margin, floor)
    }
}
