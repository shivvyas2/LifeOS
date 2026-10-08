import Foundation

/// Build configuration, read from the bundle.
///
/// Everything here is public by design: an OAuth client ID, a redirect URI and
/// a project URL. The Whoop client secret is deliberately absent: it lives only
/// in the Edge Function environment, because anything in the app bundle can be
/// read out of the `.ipa`.
enum AppConfig {
    static var whoopClientID: String? { string("WHOOPClientID") }
    static var whoopRedirectURI: String? { string("WhoopRedirectURI") }
    static var supabaseURL: URL? { string("SupabaseURL").flatMap(URL.init(string:)) }

    /// Public by design. Row Level Security protects rows, not this key.
    static var supabaseAnonKey: String? { string("SupabaseAnonKey") }

    /// ElevenLabs speech-to-text. Lives in gitignored Secrets.xcconfig.
    /// Still extractable from a shipped `.ipa` — do not log or print it.
    nonisolated static var elevenLabsAPIKey: String? { string("ElevenLabsAPIKey") }

    /// Phone OTP (Twilio Verify) lives in Edge Functions, never in the app.
    static var otpStartEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/otp-start")
    }
    /// The function that performs the confidential-client token exchange.
    static var whoopTokenEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/whoop-token")
    }

    static var fitbitClientID: String? { string("FitbitClientID") }
    static var fitbitRedirectURI: String? { string("FitbitRedirectURI") }

    /// The confidential-client exchange. Fitbit tokens never reach the app, so
    /// unlike Whoop there is no endpoint the client reads a token from: this
    /// one only ever returns a confirmation.
    static var fitbitTokenEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/fitbit-token")
    }

    static var fitbitSyncEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/fitbit-sync")
    }

    static var isFitbitConfigured: Bool {
        fitbitClientID?.isEmpty == false && fitbitRedirectURI != nil && fitbitTokenEndpoint != nil
    }

    /// The four Plaid functions live under here. The Plaid client id and
    /// secret are deliberately absent: they exist only in the function
    /// environment, because anything in the app bundle can be read out of the
    /// `.ipa`, and a Plaid secret reads every connected bank account.
    /// Public by OAuth design; the secret lives only in the function's environment.
    static var githubClientID: String? { string("GitHubClientID") }

    static var githubTokenEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/github-token")
    }

    static var isGitHubConfigured: Bool { githubClientID != nil && githubTokenEndpoint != nil }

    /// Google's iOS client id. Public by design: an iOS client has no secret.
    static var googleClientID: String? { string("GoogleClientID") }

    static var isGoogleConfigured: Bool { googleClientID?.hasSuffix(".apps.googleusercontent.com") == true }

    static var plaidFunctionsBase: URL? {
        supabaseURL?.appendingPathComponent("functions/v1")
    }

    /// Where a bank's OAuth login sends the browser when it is done.
    ///
    /// An https universal link rather than a custom scheme, because Plaid will
    /// not register a custom scheme as a redirect URI. Empty when OAuth banks
    /// are not set up, which is a working configuration: institutions that
    /// take a password inside Link still connect.
    static var plaidRedirectURI: URL? {
        string("PlaidRedirectURI").flatMap(URL.init(string:))
    }

    /// True for the redirect at the end of a bank's OAuth login, and false for
    /// every other link the app is handed. Compares host and path rather than
    /// the whole string because Plaid appends its own query parameters.
    static func isPlaidRedirect(_ url: URL) -> Bool {
        guard let redirect = plaidRedirectURI, let host = redirect.host else { return false }
        return url.host == host && url.path == redirect.path
    }

    static var isPlaidConfigured: Bool { plaidFunctionsBase != nil }

    /// Every scheme the app answers to, in the order the bundle declares them.
    ///
    /// Plural on purpose. The app carries both `almanac` and the older `lifeos`
    /// so the redirect bridge can point at either without the app and the
    /// server having to ship together; a callback arriving on any of them is
    /// ours. Checking only the first would reject the very redirect the bundle
    /// was extended to accept.
    ///
    /// Deliberately not derived from `whoopRedirectURI`. Whoop requires an
    /// https redirect, so that value points at the Edge Function bridge, and
    /// the browser only returns to the app on the final custom-scheme hop.
    static var appURLSchemes: [String] {
        guard let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else { return [] }
        return types.compactMap { $0["CFBundleURLSchemes"] as? [String] }.flatMap { $0 }
    }

    /// The preferred scheme: the first declared. For anywhere that has to name
    /// one, such as a session waiting on a single callback scheme.
    static var appURLScheme: String? { appURLSchemes.first }

    static func handles(_ scheme: String?) -> Bool {
        guard let scheme else { return false }
        return appURLSchemes.contains(scheme)
    }

    static var isWhoopConfigured: Bool {
        whoopClientID?.isEmpty == false && whoopTokenEndpoint != nil
    }

    nonisolated private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              // An unresolved build setting comes through literally.
              !value.hasPrefix("$(")
        else { return nil }
        return value
    }
}
