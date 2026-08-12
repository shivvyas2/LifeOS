import Testing
import Foundation
@testable import Integrations

/// Serves canned pages so pagination is testable without a network or a token.
final class StubURLProtocol: URLProtocol {
    /// Bodies served in order, one per request.
    nonisolated(unsafe) static var bodies: [String] = []
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        let body = Self.bodies.isEmpty ? #"{"records":[],"next_token":null}"# : Self.bodies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
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
    private func makeClient() -> WhoopClient {
        StubURLProtocol.bodies = []
        StubURLProtocol.requestedURLs = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return WhoopClient(session: URLSession(configuration: configuration))
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
