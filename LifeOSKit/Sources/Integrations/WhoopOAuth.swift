import Foundation
import CryptoKit

/// Whoop OAuth, client side only.
///
/// **This type never sees the client secret.** Whoop's token endpoint is a
/// confidential-client exchange, so it runs in an Edge Function with the secret
/// held in the server environment. A secret compiled into an iOS binary is
/// public: an `.ipa` is a zip, and `strings` finds it in seconds.
///
/// The app therefore does the half that is safe: build the authorize URL, hold
/// the PKCE verifier, and hand the returned `code` to the server.
public enum WhoopOAuth {
    public static let authorizeEndpoint = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!

    /// Every collection's scope, plus `offline` for the refresh token.
    ///
    /// Derived from `WhoopCollection` rather than listed by hand. A hand-kept
    /// list is what let the client start calling two endpoints whose scopes were
    /// never requested, which made Whoop reject a token it had just issued.
    public static let defaultScopes =
        WhoopCollection.allCases.map(\.scope) + ["offline"]

    /// One authorization attempt. `verifier` and `state` must survive until the
    /// redirect comes back, and `state` must be compared on return.
    public struct Session: Sendable, Equatable {
        public let url: URL
        public let verifier: String
        public let state: String
    }

    /// PKCE is included even though the exchange is server-side: it binds the
    /// authorization code to this specific app instance, so an intercepted
    /// redirect cannot be replayed by another client.
    public static func session(
        clientID: String,
        redirectURI: String,
        scopes: [String] = defaultScopes,
        verifier: String = randomURLSafeString(),
        state: String = randomURLSafeString(),
        /// Marks a sign-in completed in a desktop browser, which cannot hand
        /// back to a custom scheme. The bridge renders the code instead of
        /// redirecting when it sees this.
        manual: Bool = false
    ) -> Session {
        let state = manual ? "manual-" + state : state
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return Session(url: components.url!, verifier: verifier, state: state)
    }

    /// Pulls the code out of the redirect, rejecting a mismatched `state`.
    /// A mismatch means the redirect did not originate from our request, so the
    /// code is discarded rather than exchanged.
    public static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            throw WhoopAuthError.denied(error)
        }
        guard let state = items.first(where: { $0.name == "state" })?.value else {
            throw WhoopAuthError.missingState
        }
        guard state == expectedState else {
            throw WhoopAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw WhoopAuthError.missingCode
        }
        return code
    }

    /// The `state` a redirect carries, so the matching attempt can be found
    /// before its verifier is needed.
    public static func state(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    public static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }
}

public enum WhoopAuthError: Error, Equatable {
    case denied(String)
    case missingState
    case stateMismatch
    case missingCode
}

extension Data {
    /// RFC 7636 requires base64url without padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
