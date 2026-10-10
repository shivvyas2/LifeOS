import Testing
import Foundation
@testable import Integrations

/// Its own stub: the other auth suites hold their reply queues in statics, and
/// sharing one would let suites running in parallel eat each other's replies.
final class HandoffStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var reply: (Int, String) = (500, "{}")
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let (status, body) = Self.reply
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct HandoffTests {
    private func auth() -> SupabaseAuth {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HandoffStubURLProtocol.self]
        return SupabaseAuth(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon",
                            session: URLSession(configuration: config))
    }

    @Test func tradesTheTokenForANewSession() async throws {
        HandoffStubURLProtocol.reply = (200, #"""
        {"access_token":"new","refresh_token":"r2","expires_in":3600,
         "user":{"id":"u1","phone":null,"email":"s@example.com"}}
        """#)
        let session = try await auth().handoff(accessToken: "old")
        #expect(session.accessToken == "new")
        #expect(session.refreshToken == "r2")
        #expect(session.userID == "u1")
        let request = try #require(HandoffStubURLProtocol.lastRequest)
        #expect(request.url?.path == "/functions/v1/session-handoff")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func aRefusalThrowsAServerError() async {
        HandoffStubURLProtocol.reply = (401, #"{"error":"unauthorized"}"#)
        await #expect(throws: AuthError.self) { try await auth().handoff(accessToken: "old") }
    }
}
