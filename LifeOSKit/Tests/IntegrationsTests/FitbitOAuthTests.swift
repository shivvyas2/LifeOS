import Testing
import Foundation
@testable import Integrations

/// The client side of the round trip. The exchange happens on the server, so
/// what is pinned here is the half that can be got wrong silently: the
/// challenge, and the checks on the way back.
@Suite struct FitbitOAuthTests {

    private let redirect = "lifeos://fitbit-callback"

    /// Fitbit permits a custom scheme for a native app, so there is no bridge
    /// hop and the user never leaves the app. Whoop needed one because Whoop
    /// requires https.
    @Test func theAuthorizeURLCarriesEverythingFitbitRequires() throws {
        let session = FitbitOAuth.session(clientID: "ABC123", redirectURI: redirect)
        let items = try #require(URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems)
        let value = { (name: String) in items.first { $0.name == name }?.value }

        #expect(session.url.host == "www.fitbit.com")
        #expect(value("client_id") == "ABC123")
        #expect(value("response_type") == "code")
        #expect(value("redirect_uri") == redirect)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") != nil)
        #expect(value("state") == session.state)

        // The verifier itself never leaves the device at this stage.
        #expect(!session.url.absoluteString.contains(session.verifier))
        #expect(!session.url.absoluteString.contains("client_secret"))
    }

    /// RFC 7636: base64url, no padding. A padded challenge is rejected, and the
    /// rejection names nothing useful.
    @Test func theChallengeIsBase64URLWithoutPadding() {
        let challenge = FitbitOAuth.challenge(for: "a-verifier-of-some-length")
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }

    /// The scopes are space separated in one parameter, not repeated. Fitbit
    /// silently issues a narrower grant for a malformed scope list, and the
    /// first sign of it is a collection returning 403 much later.
    @Test func theScopesAreOneSpaceSeparatedParameter() throws {
        let session = FitbitOAuth.session(clientID: "ABC123", redirectURI: redirect,
                                          scopes: ["sleep", "heartrate"])
        let items = try #require(URLComponents(url: session.url, resolvingAgainstBaseURL: false)?.queryItems)
        let scopes = items.filter { $0.name == "scope" }

        #expect(scopes.count == 1)
        #expect(scopes.first?.value == "sleep heartrate")
    }

    @Test func aMatchingRedirectYieldsItsCode() throws {
        let url = URL(string: "\(redirect)?code=the-code&state=xyz")!
        #expect(try FitbitOAuth.code(from: url, expectedState: "xyz") == "the-code")
    }

    /// A mismatch means the redirect did not originate from our request, so the
    /// code is discarded rather than exchanged.
    @Test func aMismatchedStateIsRejected() {
        let url = URL(string: "\(redirect)?code=the-code&state=someone-elses")!
        #expect(throws: FitbitAuthError.stateMismatch) {
            try FitbitOAuth.code(from: url, expectedState: "xyz")
        }
    }

    @Test func aDenialIsReportedAsADenial() {
        let url = URL(string: "\(redirect)?error=access_denied&state=xyz")!
        #expect(throws: FitbitAuthError.denied("access_denied")) {
            try FitbitOAuth.code(from: url, expectedState: "xyz")
        }
    }

    @Test func aRedirectWithNoCodeIsRejected() {
        let url = URL(string: "\(redirect)?state=xyz")!
        #expect(throws: FitbitAuthError.missingCode) {
            try FitbitOAuth.code(from: url, expectedState: "xyz")
        }
    }

    /// Two taps on Connect start two valid authorizations, and whichever
    /// redirect returns must be matched by its own state. Keeping only the
    /// newest makes the earlier attempt's redirect fail as a mismatch, which
    /// looks exactly like an attack.
    @Test func theStateCanBeReadBeforeTheAttemptIsFound() {
        let url = URL(string: "\(redirect)?code=c&state=the-state")!
        #expect(FitbitOAuth.state(in: url) == "the-state")
    }

    /// An abandoned attempt must not authorise a redirect arriving much later.
    @Test func anOldAttemptIsNotFresh() {
        let pending = FitbitPendingAuth(verifier: "v", state: "s",
                                        startedAt: Date(timeIntervalSinceNow: -1_800))
        #expect(!pending.isFresh())
        #expect(FitbitPendingAuth(verifier: "v", state: "s").isFresh())
    }

    /// The app's scope list and the function's must not drift: the function
    /// pins its own list by test, and a narrower grant than the sync expects
    /// surfaces as a 403 on a collection, far from the cause.
    @Test func theScopeListMatchesTheFunctions() {
        #expect(FitbitOAuth.defaultScopes == [
            "activity", "cardio_fitness", "heartrate", "nutrition",
            "oxygen_saturation", "profile", "respiratory_rate", "sleep",
            "temperature", "weight",
        ])
    }
}
