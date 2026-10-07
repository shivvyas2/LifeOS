import Foundation

public enum GitHubAuthError: Error, Equatable {
    case denied, stateMismatch, missingCode
}

/// The authorize URL and the callback for a GitHub OAuth App, with PKCE.
public enum GitHubOAuth {
    public static let scope = "repo read:user"
    public static let redirectURI = "almanac://github-callback"

    public static func session(
        clientID: String,
        state: String = FitbitOAuth.randomURLSafeString(byteCount: 16),
        verifier: String = FitbitOAuth.randomURLSafeString()
    ) -> (url: URL, state: String, verifier: String) {
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: FitbitOAuth.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return (components.url!, state, verifier)
    }

    public static func state(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
    }

    public static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "error" })?.value == "access_denied" { throw GitHubAuthError.denied }
        guard state(in: url) == expectedState else { throw GitHubAuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw GitHubAuthError.missingCode
        }
        return code
    }
}
