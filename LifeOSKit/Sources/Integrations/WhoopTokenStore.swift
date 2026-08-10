import Foundation
import Security

/// Whoop tokens, held in the Keychain.
///
/// Not `UserDefaults`: a refresh token is a long-lived credential, and
/// `UserDefaults` is a plist in the app container that any file-level backup or
/// jailbroken read exposes. `ThisDeviceOnly` keeps it off iCloud backups too.
public struct WhoopTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Treated as expired a minute early, so a request cannot start valid and
    /// arrive expired.
    public func isExpired(now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-60) <= now
    }
}

/// The half-finished authorization: PKCE verifier and the `state` we issued.
///
/// Persisted because the sign-in happens in Safari, so the app is backgrounded
/// and may be terminated before the redirect returns. Holding this only in
/// memory means a suspended app comes back unable to verify or exchange
/// anything, and the user sees an unexplained failure.
public struct WhoopPendingAuth: Codable, Sendable, Equatable {
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

public protocol WhoopTokenStoring: Sendable {
    func load() -> WhoopTokens?
    func save(_ tokens: WhoopTokens) throws
    func clear()

    func loadPending() -> WhoopPendingAuth?
    func savePending(_ pending: WhoopPendingAuth) throws
    func clearPending()
}

public struct KeychainWhoopTokenStore: WhoopTokenStoring {
    private let service: String
    private let account: String

    public init(service: String = "ai.lifeos.whoop", account: String = "tokens") {
        self.service = service
        self.account = account
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private var baseQuery: [String: Any] { query(account) }
    private var pendingQuery: [String: Any] { query(account + ".pending") }

    public func load() -> WhoopTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(WhoopTokens.self, from: data)
    }

    public func save(_ tokens: WhoopTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { current, _ in current }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw WhoopTokenError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw WhoopTokenError.keychain(status)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    public func loadPending() -> WhoopPendingAuth? {
        read(pendingQuery).flatMap { try? JSONDecoder().decode(WhoopPendingAuth.self, from: $0) }
    }

    public func savePending(_ pending: WhoopPendingAuth) throws {
        try write(try JSONEncoder().encode(pending), to: pendingQuery)
    }

    public func clearPending() {
        SecItemDelete(pendingQuery as CFDictionary)
    }

    private func read(_ base: [String: Any]) -> Data? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
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
            guard add == errSecSuccess else { throw WhoopTokenError.keychain(add) }
        } else if status != errSecSuccess {
            throw WhoopTokenError.keychain(status)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryWhoopTokenStore: WhoopTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: WhoopTokens?
    private var pending: WhoopPendingAuth?

    public init(tokens: WhoopTokens? = nil) { self.tokens = tokens }

    public func load() -> WhoopTokens? {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }

    public func save(_ tokens: WhoopTokens) throws {
        lock.lock(); defer { lock.unlock() }
        self.tokens = tokens
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        tokens = nil
    }

    public func loadPending() -> WhoopPendingAuth? {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    public func savePending(_ pending: WhoopPendingAuth) throws {
        lock.lock(); defer { lock.unlock() }
        self.pending = pending
    }

    public func clearPending() {
        lock.lock(); defer { lock.unlock() }
        pending = nil
    }
}

public enum WhoopTokenError: Error, Equatable {
    case keychain(OSStatus)
}
