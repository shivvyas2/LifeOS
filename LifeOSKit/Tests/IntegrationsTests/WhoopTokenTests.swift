import Testing
import Foundation
@testable import Integrations

@Suite struct WhoopTokenTests {
    private func tokens(expiringIn seconds: TimeInterval) -> WhoopTokens {
        WhoopTokens(accessToken: "a", refreshToken: "r", expiresAt: .now.addingTimeInterval(seconds))
    }

    @Test func aTokenIsLiveWhileItHasComfortableTimeLeft() {
        #expect(tokens(expiringIn: 600).isExpired() == false)
    }

    @Test func anExpiredTokenIsExpired() {
        #expect(tokens(expiringIn: -1).isExpired() == true)
    }

    /// Expiry is pulled forward a minute so a request cannot start valid and
    /// arrive expired.
    @Test func aTokenAboutToExpireIsTreatedAsAlreadyExpired() {
        #expect(tokens(expiringIn: 30).isExpired() == true)
    }

    @Test func storeRoundTripsAndClears() throws {
        let store = InMemoryWhoopTokenStore()
        #expect(store.load() == nil)

        let saved = tokens(expiringIn: 3_600)
        try store.save(saved)
        #expect(store.load() == saved)

        store.clear()
        #expect(store.load() == nil)
    }
}
