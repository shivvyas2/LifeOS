import Foundation

/// Where a nudge should be delivered, as the server holds it.
///
/// The timezone rides along because the send hour is local. Without it the job
/// has no way to know when eight in the morning is for this person, and the
/// rule is that a row with no usable zone never sends: a nudge at the wrong
/// hour is worse than no nudge.
public struct PushRegistration: Sendable, Equatable {
    public let token: String
    public let timeZone: String

    public init(token: String, timeZone: String = TimeZone.current.identifier) {
        self.token = token
        self.timeZone = timeZone
    }

    public func payload(userID: String) -> [String: Any] {
        [
            "token": token,
            "user_id": userID,
            "platform": "ios",
            "timezone": timeZone,
            "updated_at": SupabaseREST.timestamp(.now),
        ]
    }
}

/// Registers and deregisters this device for proactive nudges.
///
/// Registration is keyed to the ACTIVE account, and that is a correctness
/// requirement rather than tidiness. Commit df18113 let several accounts share
/// one device: a token left registered under the account that signed out would
/// push one person's sleep data onto a phone showing somebody else's name. The
/// table makes the token its own primary key so registering under a second
/// account replaces the first account's row in one upsert, and signing out
/// deletes the row rather than orphaning it.
public struct PushTokenClient: Sendable {
    private let rest: SupabaseREST

    public init(baseURL: URL, anonKey: String, session: URLSession = .shared) {
        self.rest = SupabaseREST(baseURL: baseURL, anonKey: anonKey, session: session)
    }

    public init(rest: SupabaseREST) {
        self.rest = rest
    }

    public func register(
        _ registration: PushRegistration,
        userID: String,
        accessToken: String
    ) async throws {
        let body = try SupabaseREST.encode([registration.payload(userID: userID)])
        try await rest.upsert(table: "device_tokens", body: body, accessToken: accessToken)
    }

    /// Removes this device's registration.
    ///
    /// Called on sign out and on account switch. RLS scopes the delete to the
    /// caller's own rows, so a token that has already been claimed by another
    /// account on the same device is left alone rather than deleted out from
    /// under them.
    public func deregister(token: String, accessToken: String) async throws {
        try await rest.delete(
            table: "device_tokens",
            column: "token",
            equals: token,
            accessToken: accessToken
        )
    }
}

/// The nudge a notification carried.
///
/// Deliberately just the sentence and what it was about. The figures are not
/// in the payload: a phone that has been offline for days would otherwise open
/// on numbers two days stale, so the tap-through re-evaluates locally instead.
public struct NudgePayload: Sendable, Equatable {
    public let text: String
    public let trigger: String
    public let day: String

    public init(text: String, trigger: String, day: String) {
        self.text = text
        self.trigger = trigger
        self.day = day
    }

    /// Reads a payload out of the notification's userInfo, or nil if this is
    /// not one of ours. Nil rather than a throw: an unrecognised notification
    /// is something to ignore, not something to report.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let trigger = userInfo["trigger"] as? String,
              let day = userInfo["day"] as? String,
              let aps = userInfo["aps"] as? [AnyHashable: Any],
              let alert = aps["alert"] as? [AnyHashable: Any],
              let body = alert["body"] as? String,
              !body.isEmpty
        else { return nil }
        self.text = body
        self.trigger = trigger
        self.day = day
    }
}
