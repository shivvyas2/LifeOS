import Foundation

public enum GoogleAuthError: Error, Equatable { case denied, stateMismatch, missingCode }

public struct GoogleTokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", idToken = "id_token"
    }
}

public enum GoogleRefreshOutcome: Equatable, Sendable { case reconnect, unavailable }

/// Google sign-in for an iOS OAuth client: PKCE and no secret, the token
/// swapped and refreshed from the phone.
public enum GoogleOAuth {
    public static let scope = "openid email https://www.googleapis.com/auth/gmail.readonly"
    public static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`,
    /// the scheme Google redirects an iOS client to.
    public static func reversed(clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public static func redirectURI(clientID: String) -> String { "\(reversed(clientID: clientID)):/oauth2redirect" }

    public static func session(
        clientID: String,
        state: String = FitbitOAuth.randomURLSafeString(byteCount: 16),
        verifier: String = FitbitOAuth.randomURLSafeString()
    ) -> (url: URL, state: String, verifier: String) {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(clientID: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: FitbitOAuth.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return (components.url!, state, verifier)
    }

    public static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "error" })?.value == "access_denied" { throw GoogleAuthError.denied }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { throw GoogleAuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw GoogleAuthError.missingCode }
        return code
    }

    public static func state(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
    }

    public static func tokenRequestBody(code: String, verifier: String, clientID: String, redirectURI: String) -> Data {
        form(["grant_type": "authorization_code", "code": code, "code_verifier": verifier,
              "client_id": clientID, "redirect_uri": redirectURI])
    }

    public static func refreshRequestBody(refreshToken: String, clientID: String) -> Data {
        form(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }

    /// A refused refresh: `invalid_grant` means the grant is gone (revoked,
    /// expired after seven days in Testing); anything else is worth retrying.
    public static func refreshOutcome(status: Int, body: Data) -> GoogleRefreshOutcome {
        let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
        return (status == 400 || status == 401) && error == "invalid_grant" ? .reconnect : .unavailable
    }

    /// The `email` claim from an id token's payload. Read, not verified: it
    /// only labels the connection on this phone.
    public static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
