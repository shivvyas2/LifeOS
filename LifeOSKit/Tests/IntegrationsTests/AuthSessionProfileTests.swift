import Testing
import Foundation
@testable import Integrations

/// This suite's own stub, for the same reason `AuthErrorMappingTests` keeps one
/// apart from the Whoop suite: the reply queue is a static, and `.serialized`
/// orders tests only *within* a suite. Two suites sharing one queue would
/// consume each other's replies whenever they run at the same time.
final class ProfileStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var replies: [AuthStubURLProtocol.Reply] = []

    static func reset() { replies = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.replies.isEmpty ? AuthStubURLProtocol.Reply.status(500, "{}") : Self.replies.removeFirst()

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

/// Whether an account has been through the profile step is the only thing that
/// tells a returning user apart from a new one, since with OTP there is no
/// password and both took the identical path to get here.
@Suite(.serialized) struct AuthSessionProfileTests {
    private func makeAuth(replies: [AuthStubURLProtocol.Reply]) -> SupabaseAuth {
        ProfileStubURLProtocol.reset()
        ProfileStubURLProtocol.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileStubURLProtocol.self]
        return SupabaseAuth(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func aVerifiedUserWithAFirstNameHasAProfile() async throws {
        let auth = makeAuth(replies: [.ok(#"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,
         "user":{"id":"u1","phone":"+14155552671","email":null,
                 "user_metadata":{"first_name":"Shiv","last_name":"Vyas"}}}
        """#)])

        let session = try await auth.verify(code: "123456", destination: "+14155552671", channel: .phone)
        #expect(session.hasProfile)
    }

    @Test func aBrandNewUserHasNoProfile() async throws {
        let auth = makeAuth(replies: [.ok(#"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,
         "user":{"id":"u1","phone":"+14155552671","email":null,"user_metadata":{}}}
        """#)])

        let session = try await auth.verify(code: "123456", destination: "+14155552671", channel: .phone)
        #expect(session.hasProfile == false)
    }

    @Test func aWhitespaceOnlyFirstNameIsNotAProfile() async throws {
        let auth = makeAuth(replies: [.ok(#"""
        {"access_token":"a","refresh_token":"r","expires_in":3600,
         "user":{"id":"u1","phone":"+14155552671","email":null,
                 "user_metadata":{"first_name":"   "}}}
        """#)])

        let session = try await auth.verify(code: "123456", destination: "+14155552671", channel: .phone)
        #expect(session.hasProfile == false)
    }

    /// Sessions already in the keychain predate the key. A synthesised
    /// `init(from:)` would throw on them and sign every existing user out on
    /// upgrade, which is the worst possible cost for a new boolean.
    @Test func aStoredSessionWithoutTheKeyStillDecodes() throws {
        let blob = Data(#"""
        {"accessToken":"a","refreshToken":"r","expiresAt":800000000,
         "userID":"u1","phone":"+14155552671"}
        """#.utf8)

        let session = try JSONDecoder().decode(AuthSession.self, from: blob)
        #expect(session.accessToken == "a")
        #expect(session.userID == "u1")
        #expect(session.hasProfile == false)
    }

    /// A refresh response is allowed to be sparse. It must not erase what is
    /// already known, for the same reason `userID` and `phone` are carried.
    @Test func aRefreshDoesNotForgetTheProfile() {
        let previous = AuthSession(
            accessToken: "old", refreshToken: "r", expiresAt: .now,
            userID: "u1", phone: "+14155552671", email: nil, hasProfile: true
        )
        let refreshed = AuthSession(
            accessToken: "new", refreshToken: nil, expiresAt: .now.addingTimeInterval(3600),
            userID: "", phone: nil, email: nil, hasProfile: false
        )

        #expect(refreshed.carryingForward(previous).hasProfile)
    }

    @Test func aProfileSavedSinceTheLastRefreshSurvives() {
        let previous = AuthSession(
            accessToken: "old", refreshToken: "r", expiresAt: .now,
            userID: "u1", phone: nil, email: nil, hasProfile: false
        )
        let refreshed = AuthSession(
            accessToken: "new", refreshToken: "r2", expiresAt: .now.addingTimeInterval(3600),
            userID: "u1", phone: nil, email: nil, hasProfile: true
        )

        #expect(refreshed.carryingForward(previous).hasProfile)
    }
}
