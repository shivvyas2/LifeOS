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

    /// The function that performs the confidential-client token exchange.
    static var whoopTokenEndpoint: URL? {
        supabaseURL?.appendingPathComponent("functions/v1/whoop-token")
    }

    /// The scheme `ASWebAuthenticationSession` waits for.
    ///
    /// Deliberately not derived from `whoopRedirectURI`. Whoop requires an
    /// https redirect, so that value points at the Edge Function bridge, and
    /// the browser only returns to the app on the final `lifeos://` hop. Using
    /// the redirect's own scheme would leave the session waiting for https and
    /// the callback would never arrive.
    static var appURLScheme: String? {
        guard let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              let schemes = types.first?["CFBundleURLSchemes"] as? [String]
        else { return nil }
        return schemes.first
    }

    static var isWhoopConfigured: Bool {
        whoopClientID?.isEmpty == false && whoopTokenEndpoint != nil
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              // An unresolved build setting comes through literally.
              !value.hasPrefix("$(")
        else { return nil }
        return value
    }
}
