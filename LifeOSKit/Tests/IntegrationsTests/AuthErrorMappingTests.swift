import Testing
import Foundation
@testable import Integrations

/// OTP Edge Function errors must become a sentence, never `server(status: 502,
/// message: nil)` in the UI.
@Suite(.serialized) struct AuthErrorMappingTests {
    private func makeAuth() -> SupabaseAuth {
        AuthStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
        return SupabaseAuth(
            baseURL: URL(string: "https://project.supabase.co")!,
            anonKey: "anon",
            session: URLSession(configuration: configuration)
        )
    }

    @Test func sendFailedIsAReadableSMSFailure() async {
        let auth = makeAuth()
        AuthStubURLProtocol.replies = [
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
        AuthStubURLProtocol.replies = [
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
}
