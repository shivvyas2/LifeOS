import Foundation
import Security

/// A sign-in in flight: the verifier and state the callback must match.
/// Persisted because the web sheet can background the app long enough for
/// iOS to end it before GitHub redirects back.
public struct GitHubPendingAuth: Codable, Sendable, Equatable {
    public let verifier: String
    public let state: String
    public let createdAt: Date

    public init(verifier: String, state: String, createdAt: Date = .now) {
        self.verifier = verifier
        self.state = state
        self.createdAt = createdAt
    }

    public func isFresh(now: Date = .now, within: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(createdAt) < within
    }
}

/// The person's GitHub access. It lives only here, on the phone: the server
/// swaps the code for it and keeps nothing.
public struct GitHubConnection: Codable, Sendable, Equatable {
    public let token: String
    public let login: String

    public init(token: String, login: String) {
        self.token = token
        self.login = login
    }
}

public protocol GitHubTokenStoring: Sendable {
    func load() -> GitHubConnection?
    func save(_ connection: GitHubConnection) throws
    func clear()
    func savePending(_ pending: GitHubPendingAuth) throws
    func pending() -> GitHubPendingAuth?
    func clearPending()
}

public enum GitHubTokenStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Scoped to whichever account is open, like the Fitbit store: a GitHub
/// connection belongs to a person, not to a phone.
public struct KeychainGitHubTokenStore: GitHubTokenStoring {
    private let service: String
    private let account: String

    public init(service: String = "ai.lifeos.github", account: String? = nil) {
        self.service = service
        self.account = account
            ?? UserDefaults.standard.string(forKey: KeychainAuthSessionStore.currentAccountKey)
            ?? "pending"
    }

    private func query(_ suffix: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account + suffix,
        ]
    }

    public func load() -> GitHubConnection? {
        read(query("")).flatMap { try? JSONDecoder().decode(GitHubConnection.self, from: $0) }
    }

    public func save(_ connection: GitHubConnection) throws {
        try write(try JSONEncoder().encode(connection), to: query(""))
    }

    public func clear() { SecItemDelete(query("") as CFDictionary) }

    public func savePending(_ pending: GitHubPendingAuth) throws {
        try write(try JSONEncoder().encode(pending), to: query(".pending"))
    }

    public func pending() -> GitHubPendingAuth? {
        read(query(".pending"))
            .flatMap { try? JSONDecoder().decode(GitHubPendingAuth.self, from: $0) }
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
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
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

/// In-memory store for tests and previews.
public final class InMemoryGitHubTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: GitHubConnection?
    private var pendingAuth: GitHubPendingAuth?

    public init(connection: GitHubConnection? = nil) { self.connection = connection }

    public func load() -> GitHubConnection? { lock.lock(); defer { lock.unlock() }; return connection }
    public func save(_ connection: GitHubConnection) throws { lock.lock(); defer { lock.unlock() }; self.connection = connection }
    public func clear() { lock.lock(); defer { lock.unlock() }; connection = nil }
    public func savePending(_ pending: GitHubPendingAuth) throws { lock.lock(); defer { lock.unlock() }; pendingAuth = pending }
    public func pending() -> GitHubPendingAuth? { lock.lock(); defer { lock.unlock() }; return pendingAuth?.isFresh() == true ? pendingAuth : nil }
    public func clearPending() { lock.lock(); defer { lock.unlock() }; pendingAuth = nil }
}
