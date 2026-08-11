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

    // MARK: - Pending authorizations

    private func pending(_ state: String, startedAt: Date = .now) -> WhoopPendingAuth {
        WhoopPendingAuth(verifier: "v-\(state)", state: state, startedAt: startedAt)
    }

    /// Tapping Connect twice starts two valid authorizations. Whichever redirect
    /// comes back must find its own attempt — keeping only the newest made the
    /// first one fail as a state mismatch, which is indistinguishable from an
    /// attack.
    @Test func anEarlierAttemptSurvivesALaterOneAndIsStillMatchable() throws {
        let store = InMemoryWhoopTokenStore()
        try store.savePending(pending("first"))
        try store.savePending(pending("second"))

        let all = store.pendingAuths()
        #expect(all.count == 2)
        #expect(all.first?.state == "second")   // newest first
        #expect(all.first(where: { $0.state == "first" })?.verifier == "v-first")
    }

    /// An abandoned attempt should not authorise a redirect arriving much later.
    @Test func staleAttemptsAreNotReturned() throws {
        let store = InMemoryWhoopTokenStore()
        try store.savePending(pending("stale", startedAt: .now.addingTimeInterval(-1_800)))
        try store.savePending(pending("live"))

        #expect(store.pendingAuths().map(\.state) == ["live"])
    }

    /// A user who taps repeatedly should not accumulate credentials indefinitely.
    @Test func theListIsCappedAtTheMostRecentAttempts() throws {
        let store = InMemoryWhoopTokenStore()
        for i in 1...8 { try store.savePending(pending("s\(i)")) }

        #expect(store.pendingAuths().map(\.state) == ["s8", "s7", "s6", "s5", "s4"])
    }

    @Test func clearingPendingDropsEveryAttempt() throws {
        let store = InMemoryWhoopTokenStore()
        try store.savePending(pending("a"))
        try store.savePending(pending("b"))

        store.clearPending()
        #expect(store.pendingAuths().isEmpty)
    }
}
