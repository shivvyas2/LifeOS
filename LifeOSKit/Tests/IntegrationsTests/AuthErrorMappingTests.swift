import Testing
import Foundation
@testable import Integrations

/// The OTP suite's own stub, for the same reason `SessionRefreshTests` keeps one
/// apart from the Whoop suite: the queue is a static, and two suites sharing it
/// consume each other's replies whenever they run at the same time.
final class OTPStubURLProtocol: URLProtocol {
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

/// OTP Edge Function errors must become a sentence, never `server(status: 502,
/// message: nil)` in the UI.
@Suite(.serialized) struct AuthErrorMappingTests {
    private func makeAuth() -> SupabaseAuth {
        OTPStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OTPStubURLProtocol.self]
        return SupabaseAuth(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func sendFailedIsAReadableSMSFailure() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"send_failed"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "Couldn't send the text. Check the number and try again")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func aBlockedSMSRegionIsNamedAsSuch() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_region"}"#)
        ]

        do {
            try await auth.sendCode(to: "+919876543210", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "SMS isn't available for that country yet")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    /// The deployed Edge Function is upgraded separately from the app, so an
    /// old server still sending `sms_unverified` must not regress to a bare
    /// status code in a new build.
    @Test func theLegacyUnverifiedKindStillReads() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_unverified"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "We can't text this number yet. The SMS account is still in trial mode")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func aTrialAccountFailureBlamesTheAccountNotTheNumber() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_trial_unverified"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "We can't text this number yet. The SMS account is still in trial mode")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func anOptedOutNumberIsGivenTheRemedy() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_opted_out"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "That number opted out of our texts. Text START to our number to opt back in")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func anUnregisteredCampaignIsNamedRatherThanGeneric() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_unregistered_campaign"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "Our SMS sender isn't registered with that carrier yet")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func aCarrierBlockIsNamedRatherThanGeneric() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, #"{"error":"sms_blocked"}"#)
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "The carrier blocked that text")
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }

    @Test func anEmptyGateway502IsStillASentence() async {
        let auth = makeAuth()
        OTPStubURLProtocol.replies = [
            .status(502, "")
        ]

        do {
            try await auth.sendCode(to: "+14155552671", channel: .phone)
            Issue.record("expected sendCode to throw")
        } catch let error as AuthError {
            #expect(error.readable == "Couldn't send the text. Check the number and try again")
            if case .server(_, let message) = error {
                #expect(message != nil)
            }
        } catch {
            Issue.record("expected AuthError, got \(error)")
        }
    }
}
