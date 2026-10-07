import Foundation
import Security

/// The person's Google access. It lives only on this phone.
public struct GoogleConnection: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, email: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.email = email
    }

    /// Refreshed a minute early, so a call never leaves with a token that
    /// expires on the way.
    public func needsRefresh(now: Date = .now) -> Bool { expiresAt.timeIntervalSince(now) < 60 }
}

public struct GooglePendingAuth: Codable, Sendable, Equatable {
    public let verifier: String
    public let state: String
    public let createdAt: Date
    public init(verifier: String, state: String, createdAt: Date = .now) {
        self.verifier = verifier; self.state = state; self.createdAt = createdAt
    }
    public func isFresh(now: Date = .now) -> Bool { now.timeIntervalSince(createdAt) < 600 }
}

public protocol GoogleTokenStoring: Sendable {
    func load() -> GoogleConnection?
    func save(_ connection: GoogleConnection) throws
    func clear()
    func savePending(_ pending: GooglePendingAuth) throws
    func pending() -> GooglePendingAuth?
    func clearPending()
}

/// Per account, like the GitHub and Fitbit stores.
public struct KeychainGoogleTokenStore: GoogleTokenStoring {
    private let service: String
    private let account: String

    public init(service: String = "ai.lifeos.google", account: String? = nil) {
        self.service = service
        self.account = account
            ?? UserDefaults.standard.string(forKey: KeychainAuthSessionStore.currentAccountKey)
            ?? "pending"
    }

    private func query(_ suffix: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account + suffix]
    }

    public func load() -> GoogleConnection? {
        read(query("")).flatMap { try? JSONDecoder().decode(GoogleConnection.self, from: $0) }
    }
    public func save(_ connection: GoogleConnection) throws { try write(try JSONEncoder().encode(connection), to: query("")) }
    public func clear() { SecItemDelete(query("") as CFDictionary) }
    public func savePending(_ pending: GooglePendingAuth) throws { try write(try JSONEncoder().encode(pending), to: query(".pending")) }
    public func pending() -> GooglePendingAuth? {
        read(query(".pending")).flatMap { try? JSONDecoder().decode(GooglePendingAuth.self, from: $0) }
            .flatMap { $0.isFresh() ? $0 : nil }
    }
    public func clearPending() { SecItemDelete(query(".pending") as CFDictionary) }

    private func read(_ base: [String: Any]) -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func write(_ data: Data, to base: [String: Any]) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert.merge(attributes) { current, _ in current }
            let add = SecItemAdd(insert as CFDictionary, nil)
            guard add == errSecSuccess else { throw GitHubTokenStoreError.keychain(add) }
        } else if status != errSecSuccess {
            throw GitHubTokenStoreError.keychain(status)
        }
    }
}

public final class InMemoryGoogleTokenStore: GoogleTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: GoogleConnection?
    private var pendingAuth: GooglePendingAuth?
    public init(connection: GoogleConnection? = nil) { self.connection = connection }
    public func load() -> GoogleConnection? { lock.lock(); defer { lock.unlock() }; return connection }
    public func save(_ connection: GoogleConnection) throws { lock.lock(); defer { lock.unlock() }; self.connection = connection }
    public func clear() { lock.lock(); defer { lock.unlock() }; connection = nil }
    public func savePending(_ pending: GooglePendingAuth) throws { lock.lock(); defer { lock.unlock() }; pendingAuth = pending }
    public func pending() -> GooglePendingAuth? { lock.lock(); defer { lock.unlock() }; return pendingAuth }
    public func clearPending() { lock.lock(); defer { lock.unlock() }; pendingAuth = nil }
}
