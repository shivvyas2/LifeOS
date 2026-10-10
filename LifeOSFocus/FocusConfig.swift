import Foundation
import Integrations

/// What the Focus app reads from its Info.plist, which takes it from
/// `Config/Secrets.xcconfig`. A blank value (CI, a fresh clone) means no
/// backend, and sign-in says it is unavailable rather than failing silently.
enum FocusConfig {
    static var supabaseURL: URL? { string("SupabaseURL").flatMap(URL.init(string:)) }
    static var supabaseAnonKey: String? { string("SupabaseAnonKey") }

    static var auth: SupabaseAuth? {
        guard let url = supabaseURL, let key = supabaseAnonKey else { return nil }
        return SupabaseAuth(baseURL: url, anonKey: key)
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
