import Testing
import Foundation
@testable import Integrations

/// Serves canned auth responses. Deliberately separate from the Whoop suite's
/// stub: both hold their queues in statics, and sharing one would let the two
/// suites consume each other's responses when they run at the same time.
final class AuthStubURLProtocol: URLProtocol {
    enum Reply {
        case ok(String)
        case status(Int, String)
        /// The request never reaches a server — airplane mode, dead wifi.
        case offline
    }

    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var onRequest: (@Sendable () -> Void)?

    static func reset() {
        replies = []
        requestCount = 0
        onRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.onRequest?()
        let reply = Self.replies.isEmpty ? Reply.status(500, "{}") : Self.replies.removeFirst()

        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .ok(let body):
            send(status: 200, body: body)
        case .status(let code, let body):
            send(status: code, body: body)
        }
    }

    override func stopLoading() {}

    private func send(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

// The stub's queues are shared mutable statics, so these tests must not run
// against each other.
@Suite(.serialized) struct SessionRefreshTests {
    private func makeRefresher(store: any AuthSessionStoring) -> SessionRefresher {
        AuthStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
        let auth = SupabaseAuth(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
        return SessionRefresher(auth: auth, store: store)
    }

    private func session(expiringIn seconds: TimeInterval,
                         refreshToken: String? = "refresh-1") -> AuthSession {
        AuthSession(
            accessToken: "access-1",
            refreshToken: refreshToken,
            expiresAt: .now.addingTimeInterval(seconds),
            userID: "user-1",
            phone: "+15551234567",
            email: nil
        )
    }

    private func refreshBody(access: String, refresh: String, user: String?) -> String {
        let userJSON = user.map { #"{"id":"\#($0)","phone":"+15551234567","email":null}"# } ?? "null"
        return #"""
        {"access_token":"\#(access)","refresh_token":"\#(refresh)",
         "expires_in":3600,"user":\#(userJSON)}
        """#
    }

    @Test func logoutDuringRefreshCannotResurrectTheSession() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -60))
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [.ok(refreshBody(access: "new", refresh: "new-refresh", user: "user-1"))]
        AuthStubURLProtocol.onRequest = { store.clear() }
        #expect(await refresher.restore() == .signedOut)
        #expect(store.load() == nil)
    }

    @Test func aRefreshCannotReplaceTheAccountIdentity() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -60))
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [.ok(refreshBody(access: "other", refresh: "other-refresh", user: "user-2"))]
        #expect(await refresher.restore() == .rejected)
        #expect(store.load() == nil)
    }

    // MARK: - Nothing to restore

    @Test func withNoStoredSessionTheUserIsSignedOut() async {
        let store = InMemoryAuthSessionStore()
        let outcome = await makeRefresher(store: store).restore()

        #expect(outcome == .signedOut)
        #expect(AuthStubURLProtocol.requestCount == 0)
    }

    // MARK: - Still good

    /// A session with time left is used as-is. Refreshing it anyway would burn
    /// a network round trip on every cold launch for nothing.
    @Test func aSessionWithTimeLeftIsUsedWithoutContactingTheServer() async {
        let stored = session(expiringIn: 3_600)
        let store = InMemoryAuthSessionStore(session: stored)

        let outcome = await makeRefresher(store: store).restore()

        #expect(outcome == .active(stored))
        #expect(AuthStubURLProtocol.requestCount == 0)
    }

    // MARK: - Refreshing

    @Test func anExpiredSessionIsRefreshedAndTheNewTokensAreSaved() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -10))
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [
            .ok(refreshBody(access: "access-2", refresh: "refresh-2", user: "user-1"))
        ]

        let outcome = await refresher.restore()

        guard case .active(let restored) = outcome else {
            Issue.record("expected an active session, got \(outcome)")
            return
        }
        #expect(restored.accessToken == "access-2")
        #expect(restored.refreshToken == "refresh-2")
        #expect(restored.isExpired() == false)
        // The rotated refresh token is the one that matters: losing it means the
        // next launch tries to refresh with a token the server has retired.
        #expect(store.load()?.refreshToken == "refresh-2")
    }

    /// The magic-link path builds a session with no user id, because the tokens
    /// arrive in a URL fragment rather than a response body. A refresh that came
    /// back without a user must not erase an id we already knew.
    @Test func aRefreshedSessionKeepsTheIdentityOfTheOneItReplaces() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -10))
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [
            .ok(refreshBody(access: "access-2", refresh: "refresh-2", user: nil))
        ]

        _ = await refresher.restore()

        #expect(store.load()?.userID == "user-1")
        #expect(store.load()?.phone == "+15551234567")
    }

    /// Supabase rotates the refresh token on every use, but a response that
    /// omitted one would otherwise leave the next launch with nothing to
    /// refresh against — an unnecessary sign-out one launch later.
    @Test func aRefreshResponseWithoutARefreshTokenKeepsTheExistingOne() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -10))
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [
            .ok(#"{"access_token":"access-2","expires_in":3600,"user":null}"#)
        ]

        _ = await refresher.restore()

        #expect(store.load()?.accessToken == "access-2")
        #expect(store.load()?.refreshToken == "refresh-1")
    }

    // MARK: - Definitive rejection

    /// A revoked or reused refresh token is the one case where signing the user
    /// out is correct: the credential will never work again.
    @Test func aRefreshTokenTheServerRejectsSignsTheUserOut() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -10))
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [
            .status(400, #"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#)
        ]

        let outcome = await refresher.restore()

        #expect(outcome == .rejected)
        #expect(store.load() == nil)
    }

    @Test func anExpiredSessionWithNoRefreshTokenSignsTheUserOut() async {
        let store = InMemoryAuthSessionStore(session: session(expiringIn: -10, refreshToken: nil))
        let refresher = makeRefresher(store: store)

        let outcome = await refresher.restore()

        #expect(outcome == .rejected)
        #expect(store.load() == nil)
        #expect(AuthStubURLProtocol.requestCount == 0)
    }

    // MARK: - Failures that are not the user's fault

    /// Opening the app on a plane must not log you out. The credential is still
    /// good; only the network is missing.
    @Test func beingOfflineKeepsTheStoredSession() async {
        let stored = session(expiringIn: -10)
        let store = InMemoryAuthSessionStore(session: stored)
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [.offline]

        let outcome = await refresher.restore()

        #expect(outcome == .active(stored))
        #expect(store.load() == stored)
    }

    @Test func aServerOutageKeepsTheStoredSession() async {
        let stored = session(expiringIn: -10)
        let store = InMemoryAuthSessionStore(session: stored)
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [.status(503, #"{"msg":"service unavailable"}"#)]

        let outcome = await refresher.restore()

        #expect(outcome == .active(stored))
        #expect(store.load() == stored)
    }

    /// Rate limiting is temporary by definition, so it must not end the session.
    @Test func beingRateLimitedKeepsTheStoredSession() async {
        let stored = session(expiringIn: -10)
        let store = InMemoryAuthSessionStore(session: stored)
        let refresher = makeRefresher(store: store)
        AuthStubURLProtocol.replies = [.status(429, #"{"msg":"too many requests"}"#)]

        let outcome = await refresher.restore()

        #expect(outcome == .active(stored))
        #expect(store.load() == stored)
    }
}
