import Testing
import Foundation
@testable import Integrations

final class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.last = request
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 201,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// A resend after a lost response must be a no-op on the server, which is
/// what `ignore-duplicates` on the primary key buys.
struct SupabaseRESTPreferTests {
    @Test func resendUsesIgnoreDuplicates() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let rest = SupabaseREST(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "anon",
                                session: URLSession(configuration: config))
        try await rest.insertIgnoringDuplicates(table: "focus_sessions", body: Data("[{}]".utf8), accessToken: "t")
        #expect(RecordingURLProtocol.last?.value(forHTTPHeaderField: "Prefer")?
            .contains("resolution=ignore-duplicates") == true)
        #expect(RecordingURLProtocol.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
