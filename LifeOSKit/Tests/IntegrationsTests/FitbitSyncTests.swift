import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// This suite's own stub, for the reason the profile suite keeps one apart
/// from the Whoop suite: the reply queue is a static, and `.serialized` orders
/// tests only within a suite. Two suites sharing one queue would consume each
/// other's replies whenever they run at the same time.
final class FitbitStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = "{}"
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset(body: String = "{}", status: Int = 200) {
        Self.body = body
        Self.status = status
        Self.lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The device half of the sync. There are no tokens here to test: they live on
/// the server, because Fitbit rotates them. What is pinned is what the app does
/// with each kind of answer the function can give.
@Suite(.serialized) @MainActor struct FitbitSyncTests {

    private var day: Date {
        FitbitDerivation.parseDay("2026-08-26", calendar: .current)!
    }

    private let staged = """
    {"sleep":{"sleep":[{"dateOfSleep":"2026-08-26","efficiency":91,
      "minutesAsleep":432,"minutesAwake":48,"timeInBed":480,"type":"stages"}]}}
    """

    private func makeSync(
        body: String, status: Int = 200
    ) throws -> (FitbitSync, MetricsStore, ModelContext) {
        FitbitStubURLProtocol.reset(body: body, status: status)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FitbitStubURLProtocol.self]

        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let store = MetricsStore(context: context)
        let sync = FitbitSync(
            endpoint: URL(string: "https://example.test/functions/v1/fitbit-sync")!,
            session: URLSession(configuration: configuration),
            derivation: FitbitDerivation(store: store),
            archive: WhoopArchive(context: context)
        )
        return (sync, store, context)
    }

    @Test func aRefreshLockDoesNotBecomeAnEmptySuccessfulSync() async throws {
        let (sync, _, _) = try makeSync(body: #"{"needs_reauth":false,"payloads":{},"failures":{},"retry":true}"#)
        await #expect(throws: FitbitSyncError.retryLater) { try await sync.sync(token: "token") }
    }

    @Test func quotaRetryPreservesSuccessfullyFetchedReadings() async throws {
        let (sync, store, _) = try makeSync(body: """
        {"needs_reauth":false,"payloads":\(staged),"failures":{"hrv":"rate_limited"},"retry":true}
        """)
        await #expect(throws: FitbitSyncError.retryLater) { try await sync.sync(token: "jwt") }
        #expect(try store.metrics(from: day, to: day).first?.sleepMinutes == 432)
    }

    /// A dead credential is not a retry. The app stops and asks the user to
    /// reconnect rather than spinning against a token nothing can revive.
    @Test func aNeedsReauthResponseEndsTheSync() async throws {
        let (sync, _, _) = try makeSync(
            body: #"{"needs_reauth":true,"payloads":{},"failures":{}}"#)

        await #expect(throws: FitbitSyncError.reauthenticationRequired) {
            try await sync.sync(days: 30, token: "jwt")
        }
    }

    /// One declined scope must not lose the other collections. The write
    /// happens first and the partial failure is reported after it.
    @Test func aPartialFailureStillWritesWhatArrived() async throws {
        let (sync, store, _) = try makeSync(body: """
        {"needs_reauth":false,
         "payloads":\(staged),
         "failures":{"hrv":"forbidden_scope"}}
        """)

        await #expect(throws: FitbitSyncError.partial(failed: ["hrv"])) {
            try await sync.sync(days: 30, token: "jwt")
        }

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 432)
    }

    /// Archive first: a re-derive reads from the archive, and a payload that
    /// was never stored cannot be re-derived from.
    @Test func rawPayloadsAreArchivedBeforeTheyAreDerived() async throws {
        let (sync, _, context) = try makeSync(body: """
        {"needs_reauth":false,"payloads":\(staged),"failures":{}}
        """)

        _ = try await sync.sync(days: 30, token: "jwt")

        let archived = try context.fetch(FetchDescriptor<WhoopRawRecord>())
        #expect(archived.contains { $0.kind == "fitbit-sleep" })
    }

    /// A person with no Fitbit data is not a failure, and must not surface as
    /// one on the connections card.
    @Test func anEmptySyncIsNotAnError() async throws {
        let (sync, _, _) = try makeSync(
            body: #"{"needs_reauth":false,"payloads":{},"failures":{}}"#)

        let written = try await sync.sync(days: 30, token: "jwt")
        #expect(written == 0)
    }

    /// The caller's Supabase JWT has to reach the function, or every sync is a
    /// 401 that looks like a broken connection.
    @Test func theRequestCarriesTheCallersToken() async throws {
        let (sync, _, _) = try makeSync(
            body: #"{"needs_reauth":false,"payloads":{},"failures":{}}"#)
        _ = try await sync.sync(days: 30, token: "jwt")

        let sent = try #require(FitbitStubURLProtocol.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
    }

    /// Never connected is its own answer, and the card must offer Connect
    /// rather than reporting a failure.
    @Test func aMissingConnectionIsItsOwnError() async throws {
        let (sync, _, _) = try makeSync(body: #"{"error":"not_connected"}"#, status: 404)

        await #expect(throws: FitbitSyncError.notConnected) {
            try await sync.sync(days: 30, token: "jwt")
        }
    }

    /// A good sync reports how many days it wrote, which is what the card shows.
    @Test func aGoodSyncReportsTheDaysItWrote() async throws {
        let (sync, _, _) = try makeSync(body: """
        {"needs_reauth":false,"payloads":\(staged),"failures":{}}
        """)

        #expect(try await sync.sync(days: 30, token: "jwt") == 1)
    }
}
