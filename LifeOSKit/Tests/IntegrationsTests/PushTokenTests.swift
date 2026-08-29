import Foundation
import Testing
@testable import Integrations

@Suite("Push registration")
struct PushTokenTests {
    @Test("a registration carries the account and the zone the send hour is read in")
    func payloadCarriesAccountAndZone() {
        let payload = PushRegistration(token: "abc123", timeZone: "America/New_York")
            .payload(userID: "user-1")
        #expect(payload["token"] as? String == "abc123")
        #expect(payload["user_id"] as? String == "user-1")
        #expect(payload["platform"] as? String == "ios")
        #expect(payload["timezone"] as? String == "America/New_York")
    }

    @Test("a registration defaults to this device's own zone")
    func defaultsToCurrentZone() {
        #expect(PushRegistration(token: "abc").timeZone == TimeZone.current.identifier)
    }

    @Test("a nudge notification parses into its sentence and what it was about")
    func parsesNudgePayload() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "LIFO", "body": "Three short nights in a row."]],
            "trigger": "short_sleep",
            "day": "2026-08-28",
        ]
        let nudge = try #require(NudgePayload(userInfo: userInfo))
        #expect(nudge.text == "Three short nights in a row.")
        #expect(nudge.trigger == "short_sleep")
        #expect(nudge.day == "2026-08-28")
    }

    @Test("a notification that is not ours is ignored rather than reported")
    func ignoresForeignNotifications() {
        // No trigger: some other sender, or a future payload shape.
        #expect(NudgePayload(userInfo: ["aps": ["alert": ["body": "hi"]]]) == nil)
        // Ours, but with nothing to say. An empty body would open a
        // conversation on a blank first turn.
        #expect(NudgePayload(userInfo: [
            "aps": ["alert": ["body": ""]],
            "trigger": "short_sleep",
            "day": "2026-08-28",
        ]) == nil)
        #expect(NudgePayload(userInfo: [:]) == nil)
    }
}
