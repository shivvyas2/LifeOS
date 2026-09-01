import Testing
import Foundation
@testable import Integrations

/// Its own stub, for the reason the other auth suites keep theirs apart: the
/// recorded URL is a static, and two suites sharing one overwrite each other.
final class RefreshURLStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastURL: URL?

    static func reset() { lastURL = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        let body = """
        {"access_token":"a","refresh_token":"r","expires_in":3600}
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The refresh call is the only one of these that carries a query string, and
/// it was the only one broken.
///
/// `appendingPathComponent` treats what it is given as a single path
/// component, so it percent-encodes the `?` into `%3F`. The refresh went to
/// POST /auth/v1/token%3Fgrant_type=refresh_token, a path that does not
/// exist. GoTrue answered 404, the stored session could never be renewed, and
/// an hour after signing in every authenticated call began failing with 401:
/// profiles, device_tokens, and the coach's own turn, which surfaced as
/// "LIFO could not reach the cloud just now."
@Suite(.serialized) struct AuthRefreshURLTests {

    private func makeAuth() -> SupabaseAuth {
        RefreshURLStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshURLStubURLProtocol.self]
        return SupabaseAuth(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func theRefreshKeepsItsQueryAQueryRatherThanEscapingItIntoThePath() async {
        _ = try? await makeAuth().refresh(refreshToken: "r")

        let url = RefreshURLStubURLProtocol.lastURL
        #expect(url?.path == "/auth/v1/token")
        #expect(url?.query == "grant_type=refresh_token")
        // The exact shape of the bug, pinned so it cannot come back quietly.
        #expect(url?.absoluteString.contains("%3F") == false)
    }

    @Test func aPlainPathIsStillJustAPath() async {
        // The other callers pass no query, and must keep working unchanged.
        _ = try? await makeAuth().sendCode(to: "someone@example.com", channel: .email)

        let url = RefreshURLStubURLProtocol.lastURL
        #expect(url?.path == "/auth/v1/otp")
        #expect(url?.query == nil)
    }
}
