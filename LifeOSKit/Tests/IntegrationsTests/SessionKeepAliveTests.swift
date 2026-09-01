import Testing
import Foundation
@testable import Integrations

@Suite struct SessionKeepAliveTests {

    /// The renewal lands inside `isExpired`'s own minute of slack, or the
    /// refresher wakes, decides the session is fine, and the wake is wasted.
    @Test func theWakeIsLateEnoughForTheRefresherToActOnIt() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiresAt = now.addingTimeInterval(3600)
        let delay = SessionKeepAlive.delay(untilExpiry: expiresAt, now: now)

        #expect(delay == 3600 - SessionKeepAlive.margin)

        let session = AuthSession(
            accessToken: "a", refreshToken: "r", expiresAt: expiresAt,
            userID: "u", phone: nil, email: nil
        )
        #expect(session.isExpired(now: now.addingTimeInterval(delay)))
        // And not so early that it fires while the session is still healthy.
        #expect(!session.isExpired(now: now.addingTimeInterval(delay - 30)))
    }

    /// A session already past its expiry must not produce a zero or negative
    /// delay: that is a spin against the auth endpoint, not a retry.
    @Test func anAlreadyExpiredSessionStillWaits() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SessionKeepAlive.delay(untilExpiry: now, now: now) == SessionKeepAlive.floor)
        #expect(
            SessionKeepAlive.delay(untilExpiry: now.addingTimeInterval(-86_400), now: now)
                == SessionKeepAlive.floor
        )
    }

    /// A clock that jumps forward mid-session is the same case.
    @Test func aClockThatJumpsForwardDoesNotProduceASpin() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiresAt = now.addingTimeInterval(3600)
        let afterJump = now.addingTimeInterval(7200)
        #expect(
            SessionKeepAlive.delay(untilExpiry: expiresAt, now: afterJump)
                == SessionKeepAlive.floor
        )
    }
}
