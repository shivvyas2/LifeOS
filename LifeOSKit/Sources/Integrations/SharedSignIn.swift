import Foundation
import Security

/// What a signed-in LifeOS app leaves for its siblings: an access token, never
/// the refresh token.
///
/// Supabase rotates the refresh token on every refresh and revokes the family
/// when a used one is presented again, so two apps holding one refresh token
/// would sign each other out. A sibling instead trades this short-lived access
/// token at `session-handoff` for a session entirely its own.
public struct SignInBeacon: Codable, Equatable, Sendable {
    public let userID: String
    public let label: String
    public let accessToken: String
    public let expiresAt: Date

    public init(userID: String, label: String, accessToken: String, expiresAt: Date) {
        self.userID = userID; self.label = label; self.accessToken = accessToken; self.expiresAt = expiresAt
    }
}

public protocol BeaconKeychain: Sendable {
    func read() -> Data?
    func write(_ data: Data)
    func delete()
}

public enum SharedSignIn {
    /// Set once at launch by an app whose entitlements include the shared
    /// group. Nil (tests, extensions, the watch) turns every call into a no-op.
    nonisolated(unsafe) public static var accessGroup: String?

    /// A handoff is a network round trip; a token about to lapse would be
    /// refused on arrival.
    static let minimumRemaining: TimeInterval = 120

    public static func publish(_ session: AuthSession, keychain: (any BeaconKeychain)? = nil) {
        guard let store = resolve(keychain) else { return }
        let beacon = SignInBeacon(userID: session.userID,
                                  label: session.email ?? session.phone ?? "your account",
                                  accessToken: session.accessToken, expiresAt: session.expiresAt)
        guard let data = try? JSONEncoder().encode(beacon) else { return }
        store.write(data)
    }

    public static func current(now: Date = .now, keychain: (any BeaconKeychain)? = nil) -> SignInBeacon? {
        guard let beacon = read(resolve(keychain)),
              beacon.expiresAt.timeIntervalSince(now) > minimumRemaining else { return nil }
        return beacon
    }

    /// Removes the beacon only if it is this account's, so signing out of one
    /// account never hides another account a sibling app could still offer.
    public static func withdraw(userID: String, keychain: (any BeaconKeychain)? = nil) {
        let store = resolve(keychain)
        guard let beacon = read(store), beacon.userID == userID else { return }
        store?.delete()
    }

    /// No group, no sharing: an explicit keychain is still ignored, so a build
    /// without the entitlement can never write a beacon by accident.
    private static func resolve(_ keychain: (any BeaconKeychain)?) -> (any BeaconKeychain)? {
        guard let group = accessGroup else { return nil }
        return keychain ?? GroupKeychain(group: group)
    }

    private static func read(_ store: (any BeaconKeychain)?) -> SignInBeacon? {
        guard let data = store?.read() else { return nil }
        return try? JSONDecoder().decode(SignInBeacon.self, from: data)
    }
}

/// The real store: one generic password in the shared access group.
struct GroupKeychain: BeaconKeychain {
    let group: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ai.lifeos.signin-beacon",
         kSecAttrAccount as String: "beacon",
         kSecAttrAccessGroup as String: group]
    }

    func read() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func write(_ data: Data) {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func delete() { SecItemDelete(query as CFDictionary) }
}
