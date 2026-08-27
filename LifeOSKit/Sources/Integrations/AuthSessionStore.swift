import Foundation
import Security

/// Persists the signed-in session. Keychain, not UserDefaults: a refresh token
/// grants a new access token indefinitely, so it is a credential in its own
/// right.
public protocol AuthSessionStoring: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear()
}

public struct KeychainAuthSessionStore: AuthSessionStoring {
    private let service: String
    private let account: String

    /// The slot every build before accounts used. Kept as a name so the
    /// upgrade path can find the session already on the device.
    public static let legacyAccount = "session"
    /// Where the current account id is recorded. Read directly rather than
    /// through `AccountStore`, which is main-actor bound while this type is
    /// used from wherever a network call happens to be made.
    public static let currentAccountKey = "accounts.current"

    /// Defaults to whichever account is current.
    ///
    /// This matters more than it looks. Every network client in the app builds
    /// one of these to get a token, and before accounts there was one slot, so
    /// after a switch they would all have carried on presenting the previous
    /// account's access token and reading the previous account's rows.
    public init(service: String = "ai.lifeos.auth", account: String? = nil) {
        self.service = service
        self.account = account
            ?? UserDefaults.standard.string(forKey: Self.currentAccountKey)
            ?? Self.legacyAccount
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> AuthSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let add = SecItemAdd(insert as CFDictionary, nil)
            guard add == errSecSuccess else { throw AuthStoreError.keychain(add) }
        } else if status != errSecSuccess {
            throw AuthStoreError.keychain(status)
        }
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}

public final class InMemoryAuthSessionStore: AuthSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?
    public init(session: AuthSession? = nil) { self.session = session }
    public func load() -> AuthSession? { lock.lock(); defer { lock.unlock() }; return session }
    public func save(_ session: AuthSession) throws { lock.lock(); defer { lock.unlock() }; self.session = session }
    public func clear() { lock.lock(); defer { lock.unlock() }; session = nil }
}

public enum AuthStoreError: Error, Equatable { case keychain(OSStatus) }
