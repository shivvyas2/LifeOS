import Foundation
import Insights
import Integrations

/// Where a conversation's cloud tier comes from.
///
/// The same six lines used to sit in both `CoachViewModel` and
/// `AssistantViewModel`, one as a stored property and one rebuilt on every
/// send. That mattered more than duplication usually does: the engine is
/// what carries the user's data to the provider, and a second copy is a
/// second place for that wiring to be got subtly wrong.
enum ChatTier {

    /// The cloud engine, or nil when the project is not configured for one.
    ///
    /// `nil` is a real shipping state rather than a stub: with no Supabase
    /// URL the app still answers on-device and says so when it cannot reach
    /// further.
    ///
    /// The access token is read per call rather than captured, because the
    /// session is refreshed while the app runs and a copy taken at launch
    /// would go stale within the hour.
    static func remote() -> (any ChatEngine)? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey
        else { return nil }
        let sessions = KeychainAuthSessionStore()
        return RemoteChatEngine(baseURL: url, anonKey: key, accessToken: {
            sessions.load()?.accessToken
        })
    }
}
