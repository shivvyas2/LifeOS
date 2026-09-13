import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// Serves canned pages so pagination is testable without a network or a token.
final class StubURLProtocol: URLProtocol {
    /// Bodies served in order, one per request.
    nonisolated(unsafe) static var bodies: [String] = []
    nonisolated(unsafe) static var requestedURLs: [URL] = []
    /// Status codes served in order, one per request. Empty means 200 for all,
    /// so every existing test is unaffected.
    nonisolated(unsafe) static var statuses: [Int] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        let body = Self.bodies.isEmpty ? #"{"records":[],"next_token":null}"# : Self.bodies.removeFirst()
        let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// StubURLProtocol's canned-body queue is shared mutable static state, so tests
// in this suite must not run concurrently or one test's makeClient() reset
// races another's in-flight requests.
@Suite(.serialized) struct WhoopPaginationTests {
    /// Resets the stub's queues and returns a session wired to it. Both the
    /// client and the token exchange must use this one: an exchange left on
    /// `URLSession.shared` reaches the real network and fails DNS instead of
    /// returning the status the test asked for.
    private func stubSession() -> URLSession {
        StubURLProtocol.bodies = []
        StubURLProtocol.requestedURLs = []
        StubURLProtocol.statuses = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient() -> WhoopClient {
        WhoopClient(session: stubSession())
    }

    private func cyclePage(id: Int, next: String?) -> String {
        let token = next.map { "\"\($0)\"" } ?? "null"
        return """
        {"records":[{"id":\(id),"start":"2026-08-10T10:00:00Z","score_state":"SCORED",
          "score":{"strain":1.0,"kilojoule":100,"average_heart_rate":60,"max_heart_rate":100}}],
         "next_token":\(token)}
        """
    }

    @Test func everyPageIsFollowedUntilTheTokenIsNil() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = [
            cyclePage(id: 1, next: "t1"),
            cyclePage(id: 2, next: "t2"),
            cyclePage(id: 3, next: nil),
        ]

        let samples = try await client.cycles(accessToken: "x", since: .now, until: .now)
        #expect(samples.count == 3)
        #expect(StubURLProtocol.requestedURLs.count == 3)
    }

    @Test func theFollowUpRequestCarriesTheNextToken() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = [cyclePage(id: 1, next: "abc"), cyclePage(id: 2, next: nil)]

        _ = try await client.cycles(accessToken: "x", since: .now, until: .now)
        let second = try #require(StubURLProtocol.requestedURLs.last?.absoluteString)
        #expect(second.contains("nextToken=abc"))
    }

    @Test func aSinglePageMakesOneRequest() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = [cyclePage(id: 1, next: nil)]

        let samples = try await client.cycles(accessToken: "x", since: .now, until: .now)
        #expect(samples.count == 1)
        #expect(StubURLProtocol.requestedURLs.count == 1)
    }

    /// A server that always returns a token must not spin forever.
    @Test func thePageCapBoundsARunawayResponse() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = (0..<40).map { cyclePage(id: $0, next: "always") }

        let samples = try await client.cycles(accessToken: "x", since: .now, until: .now)
        #expect(StubURLProtocol.requestedURLs.count == 20)
        #expect(samples.count == 20)
    }

    // MARK: - A collection's 401 is not a dead token

    @MainActor
    private func makeSync(session: URLSession, tokens: WhoopTokenStoring) throws -> WhoopSync {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let archive = WhoopArchive(context: context)
        return WhoopSync(
            client: WhoopClient(session: session),
            exchange: WhoopTokenExchange(
                endpoint: URL(string: "https://stub.invalid/token")!, session: session
            ),
            tokens: tokens,
            derivation: WhoopDerivation(store: MetricsStore(context: context), archive: archive),
            archive: archive
        )
    }

    /// The bug this guards: a 401 from one collection deleted the credential the
    /// user had just granted, so connecting again immediately failed again and
    /// the loop could never break. A collection rejecting a live token is a
    /// permission problem, most often a scope granted before the app asked for
    /// it, and the connection must survive it.
    @Test @MainActor func aCollectionRejectionKeepsTheConnection() async throws {
        let session = stubSession()
        let tokens = InMemoryWhoopTokenStore(tokens: WhoopTokens(
            accessToken: "live", refreshToken: "refresh",
            expiresAt: .now.addingTimeInterval(3_600)
        ))
        StubURLProtocol.statuses = [401]

        let sync = try makeSync(session: session, tokens: tokens)
        await #expect(throws: WhoopSyncError.accessDenied) {
            try await sync.sync()
        }
        #expect(tokens.load() != nil, "a collection's 401 must not delete the token")
    }

    /// The one 401 that does mean the connection is over: the refresh token
    /// itself was rejected, so nothing the app holds can be used again.
    @Test @MainActor func aRejectedRefreshDoesClearTheConnection() async throws {
        let session = stubSession()
        let tokens = InMemoryWhoopTokenStore(tokens: WhoopTokens(
            accessToken: "stale", refreshToken: "refresh",
            expiresAt: .now.addingTimeInterval(-3_600)      // forces a refresh
        ))
        StubURLProtocol.statuses = [502]
        StubURLProtocol.bodies = [#"{"error":"exchange_failed","status":401}"#]

        let sync = try makeSync(session: session, tokens: tokens)
        await #expect(throws: WhoopSyncError.reauthenticationRequired) {
            try await sync.sync()
        }
        #expect(tokens.load() == nil, "a dead refresh token must clear the connection")
    }

    @Test @MainActor func anExpiredAppSessionKeepsTheWhoopConnection() async throws {
        let session = stubSession()
        let tokens = InMemoryWhoopTokenStore(tokens: WhoopTokens(
            accessToken: "stale", refreshToken: "refresh",
            expiresAt: .now.addingTimeInterval(-3_600)
        ))
        StubURLProtocol.statuses = [401]
        StubURLProtocol.bodies = [#"{"error":"unauthorized"}"#]
        let sync = try makeSync(session: session, tokens: tokens)
        await #expect(throws: WhoopTokenExchangeError.self) { try await sync.sync() }
        #expect(tokens.load()?.refreshToken == "refresh")
    }

    /// OAuth servers commonly report an expired or rotated refresh token as
    /// `400 invalid_grant`, not 401. It is still a permanent credential failure.
    @Test @MainActor func anInvalidGrantRefreshClearsTheConnection() async throws {
        let session = stubSession()
        let tokens = InMemoryWhoopTokenStore(tokens: WhoopTokens(
            accessToken: "stale", refreshToken: "refresh",
            expiresAt: .now.addingTimeInterval(-3_600)
        ))
        StubURLProtocol.statuses = [400]

        let sync = try makeSync(session: session, tokens: tokens)
        await #expect(throws: WhoopSyncError.reauthenticationRequired) {
            try await sync.sync()
        }
        #expect(tokens.load() == nil)
    }
}

/// The scope list and the endpoint list are two things that must agree, and
/// nothing checked that they did. Shipping `/v2/activity/workout` and
/// `/v2/user/measurement/body` without `read:workout` and
/// `read:body_measurement` made every sync 401 on a freshly granted token.
@Suite struct WhoopScopeContractTests {
    @Test func everyCollectionsScopeIsRequestedAtAuthorization() {
        for collection in WhoopCollection.allCases {
            #expect(
                WhoopOAuth.defaultScopes.contains(collection.scope),
                "\(collection.path) needs \(collection.scope), which is not requested"
            )
        }
    }

    @Test func theAuthorizeURLCarriesEveryCollectionsScope() throws {
        let session = WhoopOAuth.session(clientID: "id", redirectURI: "lifeos://cb")
        let items = try #require(URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems)
        let granted = Set((items.first { $0.name == "scope" }?.value ?? "").split(separator: " ").map(String.init))

        for collection in WhoopCollection.allCases {
            #expect(granted.contains(collection.scope), "authorize URL omits \(collection.scope)")
        }
    }

    /// Without this the app cannot refresh, and every expiry becomes a manual
    /// reconnection.
    @Test func offlineIsRequestedSoTheTokenCanBeRefreshed() {
        #expect(WhoopOAuth.defaultScopes.contains("offline"))
    }

    @Test func everyCollectionHasADistinctPathAndScope() {
        let paths = WhoopCollection.allCases.map(\.path)
        let scopes = WhoopCollection.allCases.map(\.scope)
        #expect(Set(paths).count == paths.count)
        #expect(Set(scopes).count == scopes.count)
    }
}

// Add to the existing WhoopPaginationTests file. Do NOT declare a second stub
// with the same shared-statics pattern: `.serialized` scopes to one suite, so
// two suites sharing statics race again even with the trait on both.
@Suite struct WhoopRawSplitTests {
    @Test func eachRecordBecomesItsOwnPayloadKeyedByID() throws {
        let page = #"{"records":[{"id":"a","v":1},{"id":"b","v":2}],"next_token":null}"#
        let split = try WhoopRawSplit.records(inPage: Data(page.utf8))
        #expect(split.map(\.externalID) == ["a", "b"])
        #expect(String(decoding: split[0].payload, as: UTF8.self).contains("\"v\":1"))
    }

    /// Recovery records have no id of their own; they are keyed by the cycle
    /// they score. Without this they would all collide on one archive row.
    @Test func recoveryIsKeyedByItsCycle() throws {
        let page = #"{"records":[{"cycle_id":123,"score_state":"SCORED"}],"next_token":null}"#
        #expect(try WhoopRawSplit.records(inPage: Data(page.utf8)).map(\.externalID) == ["123"])
    }

    @Test func numericIDsBecomeStrings() throws {
        let page = #"{"records":[{"id":99}],"next_token":null}"#
        #expect(try WhoopRawSplit.records(inPage: Data(page.utf8)).map(\.externalID) == ["99"])
    }

    /// A record with no usable identity is skipped rather than archived under a
    /// made-up key that a later sync could never match.
    @Test func recordsWithNoIdentityAreSkipped() throws {
        let page = #"{"records":[{"noise":1},{"id":"ok"}],"next_token":null}"#
        #expect(try WhoopRawSplit.records(inPage: Data(page.utf8)).map(\.externalID) == ["ok"])
    }

    @Test func anEmptyPageSplitsToNothing() throws {
        let page = #"{"records":[],"next_token":null}"#
        #expect(try WhoopRawSplit.records(inPage: Data(page.utf8)).isEmpty)
    }
}
