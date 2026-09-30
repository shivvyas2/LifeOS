import Foundation

/// Security architecture documentation for OAuth integrations.
///
/// This file documents the security decisions made in the integration layer,
/// explaining why tokens go in the Keychain, how PKCE protects against
/// interception, and why the confidential client secret lives server-side.
///
/// **Key Decision: Keychain over UserDefaults**
///
/// Refresh tokens are long-lived credentials. `UserDefaults` is a plist file
/// in the app container that:
/// - File-level backups expose
/// - Jailbroken devices can read
/// - Other apps could potentially access (on jailbroken devices)
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps tokens:
/// - In the Keychain (iOS's secure credential store)
/// - Off iCloud backups (`ThisDeviceOnly`)
/// - Available only after device unlock (`AfterFirstUnlock`)
///
/// **PKCE (Proof Key for Code Exchange)**
///
/// OAuth flow for public clients (native apps) that cannot securely store a
/// client secret. PKCE prevents authorization code interception attacks.
///
/// Flow:
/// 1. App generates random `verifier` and derives `challenge` from it
/// 2. App saves `verifier` to Keychain (in case iOS terminates the app)
/// 3. App opens Safari with authorization URL + `challenge`
/// 4. User logs in, Whoop redirects back with `code`
/// 5. App loads `verifier` from Keychain
/// 6. App sends `code` + `verifier` to Edge Function
/// 7. Edge Function exchanges `code` + `verifier` + `client_secret` for tokens
/// 8. Edge Function returns tokens to app
/// 9. App stores tokens in Keychain
///
/// Attack prevented:
/// - Attacker intercepts the `code` from redirect
/// - Attacker cannot exchange it (lacks `verifier`)
/// - Only the app that started the flow has the `verifier`
///
/// **Confidential Client Secret**
///
/// Whoop requires a client secret for token exchange. This secret MUST live
/// server-side because anything in the app bundle can be extracted from an
/// `.ipa` file.
///
/// Architecture:
/// - Client ID: In app bundle (public by design)
/// - Client secret: In Edge Function environment (never leaves server)
/// - Edge Function performs the token exchange as confidential client
/// - App only receives the final tokens
///
/// **Fitbit Difference**
///
/// Fitbit rotates its refresh token on every use, so only ONE writer can hold
/// it. The database row is that writer, not the app. `FitbitConnectionViewModel`
/// never loads, stores or refreshes tokens; it only:
/// 1. Performs OAuth to get a `code`
/// 2. Sends `code` to Edge Function
/// 3. Asks server for connection state
///
/// This prevents token conflicts when the same account is open on multiple
/// devices: the server is the authority, and each device asks it for state.
///
/// **Scope Per Account**
///
/// Every keychain item is scoped to the current account ID:
///
/// ```swift
/// public init(account: String? = nil) {
///     let account = account
///         ?? UserDefaults.standard.string(forKey: "currentAccountID")
///         ?? "tokens"
///     self.account = account
/// }
/// ```
///
/// Why: A Whoop connection belongs to a person, not to a phone. Without this,
/// the second account to sign in would inherit the first one's strap and sync
/// their recovery scores into the wrong store.
///
/// **DI Container and Security**
///
/// The `IntegrationContainer` DI pattern does NOT change security:
/// - Production: Still uses `KeychainWhoopTokenStore`
/// - Tests: Uses in-memory `MockWhoopTokenStore` (no real tokens)
///
/// DI improves testability, not security. Token storage remains in Keychain.
///
/// **What Goes in UserDefaults**
///
/// Only non-sensitive state caching:
/// - "Is Fitbit connected?" (boolean, cached while server is queried)
/// - "Last synced days" (number, for UI display)
/// - Onboarding step (enum, for resuming signup)
///
/// These are not credentials and do not grant access to anything.
///
/// **Threat Model**
///
/// Protected against:
/// - ✅ Authorization code interception (PKCE)
/// - ✅ Client secret extraction from .ipa (lives server-side)
/// - ✅ Token exposure in backups (ThisDeviceOnly)
/// - ✅ Other apps reading tokens (Keychain isolation)
/// - ✅ Fitbit token conflicts (server is authority)
///
/// Not protected against:
/// - ❌ Jailbroken device with root access (Keychain can be read)
/// - ❌ Physical device access while unlocked (tokens are available)
/// - ❌ Compromised Edge Function (has client secret)
///
/// Acceptable tradeoffs: A jailbroken device has already bypassed iOS security,
/// and a compromised server is a systemic failure no client-side architecture
/// can prevent.
///
/// **Testing Without Compromising Security**
///
/// The DI container allows injecting mock stores in tests:
///
/// ```swift
/// let mockStore = MockWhoopTokenStore()
/// let container = IntegrationContainer.test(whoopTokenStore: mockStore)
/// ```
///
/// Mock stores:
/// - Hold tokens in memory (fast, no I/O)
/// - Are isolated per test (no shared state)
/// - Never touch the real Keychain
/// - Use fixture data (not real credentials)
///
/// Production code still uses the real Keychain stores; mocks are test-only.

enum SecurityArchitecture {
    /// Documents why PKCE is needed and how it works.
    ///
    /// PKCE = Proof Key for Code Exchange (RFC 7636)
    /// Designed for native apps that cannot keep a client secret confidential.
    enum PKCE {
        /// Random string generated by the client, held in Keychain during OAuth.
        typealias Verifier = String
        
        /// SHA-256 hash of the verifier, sent in the authorization request.
        /// The authorization server binds the code to this challenge.
        typealias Challenge = String
        
        /// Authorization code returned by Whoop after user login.
        /// Can only be exchanged by presenting the verifier that matches the
        /// challenge it was bound to.
        typealias Code = String
    }
    
    /// Documents why tokens go in Keychain, not UserDefaults.
    enum TokenStorage {
        case keychain       // ✅ Production: secure, isolated, excludable from backups
        case userDefaults   // ❌ Never for tokens: plist file, exposed in backups
        case inMemory       // ⚠️  Tests only: fast, isolated, no persistence
    }
    
    /// Documents why the client secret lives server-side.
    enum ClientSecret {
        case edgeFunction   // ✅ Correct: environment variable on server
        case appBundle      // ❌ Wrong: extractable from .ipa
        case keychain       // ❌ Wrong: still in .ipa as fallback, can be dumped
    }
}
