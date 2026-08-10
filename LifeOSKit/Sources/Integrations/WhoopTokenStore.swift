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

public protocol WhoopTokenStoring: Sendable {
    func load() -> WhoopTokens?
    func save(_ tokens: WhoopTokens) throws
    func clear()
}

public struct KeychainWhoopTokenStore: WhoopTokenStoring {
    private let service: String
    private let account: String

    public init(service: String = "ai.lifeos.whoop", account: String = "tokens") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

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
}

/// In-memory store for tests and previews.
public final class InMemoryWhoopTokenStore: WhoopTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: WhoopTokens?

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
}

public enum WhoopTokenError: Error, Equatable {
    case keychain(OSStatus)
}
