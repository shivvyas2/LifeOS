import Foundation
import CryptoKit

/// Fitbit OAuth, client side only.
///
/// **This type never sees the client secret, and never sees a token either.**
/// The exchange runs in an Edge Function, and unlike Whoop the tokens stay
/// there: Fitbit rotates the refresh token on every use, so exactly one writer
/// may hold it.
///
/// The app does the half that is safe: build the authorize URL, hold the PKCE
/// verifier, and hand the returned `code` to the server.
public enum FitbitOAuth {
    public static let authorizeEndpoint = URL(string: "https://www.fitbit.com/oauth2/authorize")!

    /// Every scope the app reads. Kept in step with `FITBIT_SCOPES` in
    /// `supabase/functions/_shared/fitbit.ts`, which is pinned by its own test,
    /// because a narrower grant than the sync expects surfaces as a 403 on a
    /// collection, far from the cause.
    public static let defaultScopes = [
        "activity", "cardio_fitness", "heartrate", "nutrition",
        "oxygen_saturation", "profile", "respiratory_rate", "sleep",
        "temperature", "weight",
    ]

    /// One authorization attempt. `verifier` and `state` must survive until the
    /// redirect comes back, and `state` must be compared on return.
    public struct Session: Sendable, Equatable {
        public let url: URL
        public let verifier: String
        public let state: String
    }

    /// PKCE binds the authorization code to this app instance, so an
    /// intercepted redirect cannot be replayed by another client.
    public static func session(
        clientID: String,
        redirectURI: String,
        scopes: [String] = defaultScopes,
        verifier: String = randomURLSafeString(),
        state: String = randomURLSafeString()
    ) -> Session {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            // One parameter, space separated. Repeating the parameter makes
            // Fitbit issue a narrower grant without saying so, and the first
            // sign of it is a collection returning 403 much later.
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
            throw FitbitAuthError.denied(error)
        }
        guard let state = items.first(where: { $0.name == "state" })?.value else {
            throw FitbitAuthError.missingState
        }
        guard state == expectedState else {
            throw FitbitAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw FitbitAuthError.missingCode
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

public enum FitbitAuthError: Error, Equatable {
    case denied(String)
    case missingState
    case stateMismatch
    case missingCode
}
