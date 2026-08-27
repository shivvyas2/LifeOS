import Foundation
import Security

/// The half-finished authorization: PKCE verifier and the `state` we issued.
///
/// Persisted because the sign-in happens in a web session, so the app is
/// backgrounded and may be terminated before the redirect returns. Holding
/// this only in memory means a suspended app comes back unable to verify or
/// exchange anything, and the user sees an unexplained failure.
public struct FitbitPendingAuth: Codable, Sendable, Equatable {
    public let verifier: String
    public let state: String
    public let startedAt: Date

    public init(verifier: String, state: String, startedAt: Date = .now) {
        self.verifier = verifier
        self.state = state
        self.startedAt = startedAt
    }

    /// An abandoned attempt should not authorise a redirect arriving much later.
    public func isFresh(now: Date = .now, within: TimeInterval = 900) -> Bool {
        now.timeIntervalSince(startedAt) < within
    }
}

/// Deliberately has no token methods.
///
/// This is the whole difference from `WhoopTokenStoring`, and it is not an
/// oversight: Fitbit rotates its refresh token on every use, so exactly one
/// writer may hold it, and that writer is a row in the database. There is no
/// Fitbit credential on the device to store, load or clear.
public protocol FitbitAuthStoring: Sendable {
    /// All in-flight attempts, newest first.
    ///
    /// A list rather than one slot: tapping Connect twice starts two valid
    /// authorizations, and whichever redirect returns must be matched by its
    /// own `state`. Keeping only the newest made an earlier attempt's redirect
    /// fail as a state mismatch, which looks exactly like an attack.
    func pendingAuths() -> [FitbitPendingAuth]
    func savePending(_ pending: FitbitPendingAuth) throws
    func clearPending()
}

/// Pending attempts, held in the Keychain.
///
/// Not `UserDefaults`: a PKCE verifier is the secret half of an in-flight
/// authorization, and `UserDefaults` is a plist in the app container that any
/// file-level backup or jailbroken read exposes. `ThisDeviceOnly` keeps it off
/// iCloud backups too.
public struct KeychainFitbitAuthStore: FitbitAuthStoring {
    private let service: String
    private let account: String

    /// Scoped to whichever account is open. A Fitbit connection belongs to a
    /// person, not to a phone: without this, the second account to sign in
    /// would be able to complete the first one's authorization.
    public init(
        service: String = "ai.lifeos.fitbit",
        account: String? = nil
    ) {
        let account = account
            ?? UserDefaults.standard.string(forKey: KeychainAuthSessionStore.currentAccountKey)
            ?? "pending"
        self.service = service
        self.account = account
    }

    private var pendingQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account + ".pending",
        ]
    }

    public func pendingAuths() -> [FitbitPendingAuth] {
        guard let data = read(pendingQuery),
              let all = try? JSONDecoder().decode([FitbitPendingAuth].self, from: data)
        else { return [] }
        return all.filter { $0.isFresh() }
    }

    public func savePending(_ pending: FitbitPendingAuth) throws {
        // Cap the list: a user who taps repeatedly should not accumulate
        // credentials indefinitely, and anything stale is dropped anyway.
        let kept = ([pending] + pendingAuths()).prefix(5)
        try write(try JSONEncoder().encode(Array(kept)), to: pendingQuery)
    }

    public func clearPending() {
        SecItemDelete(pendingQuery as CFDictionary)
    }

    private func read(_ base: [String: Any]) -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func write(_ data: Data, to base: [String: Any]) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert.merge(attributes) { current, _ in current }
            let add = SecItemAdd(insert as CFDictionary, nil)
            guard add == errSecSuccess else { throw FitbitAuthStoreError.keychain(add) }
        } else if status != errSecSuccess {
            throw FitbitAuthStoreError.keychain(status)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryFitbitAuthStore: FitbitAuthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [FitbitPendingAuth] = []

    public init() {}

    public func pendingAuths() -> [FitbitPendingAuth] {
        lock.lock(); defer { lock.unlock() }
        return pending.filter { $0.isFresh() }
    }

    public func savePending(_ pending: FitbitPendingAuth) throws {
        lock.lock(); defer { lock.unlock() }
        self.pending = Array(([pending] + self.pending).prefix(5))
    }

    public func clearPending() {
        lock.lock(); defer { lock.unlock() }
        pending = []
    }
}

public enum FitbitAuthStoreError: Error, Equatable {
    case keychain(OSStatus)
}
