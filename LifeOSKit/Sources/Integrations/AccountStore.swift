import Foundation
import Persistence

/// One signed-in account on this device.
public struct Account: Codable, Sendable, Equatable, Identifiable {
    public let userID: String
    /// The email or phone the account signed in with, for the switcher. Not a
    /// credential, and never the only way an account is identified: the id is.
    public let label: String
    public let addedAt: Date

    public var id: String { userID }
    public var scope: UserScope { UserScope(id: userID) }

    public init(userID: String, label: String, addedAt: Date = .now) {
        self.userID = userID
        self.label = label
        self.addedAt = addedAt
    }
}

/// Every account signed in on this device, and which one is current.
///
/// Sessions stay in the keychain, one item per user, because a refresh token
/// grants a new access token indefinitely and is a credential in its own
/// right. The roster, which is only ids and labels, sits in defaults: a list
/// of who has used this phone is not a secret, and keeping it out of the
/// keychain means enumerating accounts does not need a keychain read per
/// account.
///
/// Before this, one keychain slot held one session, so signing in as a second
/// person overwrote the first and there was no way back to them.
@MainActor
public final class AccountStore {
    private static let rosterKey = "accounts.roster"
    private static let currentKey = "accounts.current"

    private let defaults: UserDefaults
    /// How a session store is obtained for one account. Injected so the roster
    /// logic can be tested without touching the real keychain, which on a test
    /// machine means either a prompt or a permission dance.
    private let sessionStores: (String) -> any AuthSessionStoring

    public init(
        defaults: UserDefaults = .standard,
        keychainService: String = "ai.lifeos.auth"
    ) {
        self.defaults = defaults
        self.sessionStores = { userID in
            KeychainAuthSessionStore(service: keychainService, account: userID)
        }
    }

    public init(
        defaults: UserDefaults,
        sessionStores: @escaping (String) -> any AuthSessionStoring
    ) {
        self.defaults = defaults
        self.sessionStores = sessionStores
    }

    // MARK: - Roster

    public var accounts: [Account] {
        guard let data = defaults.data(forKey: Self.rosterKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data)
        else { return [] }
        return decoded.sorted { $0.addedAt < $1.addedAt }
    }

    /// The account whose data is loaded, or nil when nobody is signed in.
    ///
    /// Nil rather than "the first account we can find": a current id naming an
    /// account that has been signed out must never silently open somebody
    /// else's store.
    public var currentScope: UserScope? {
        guard let id = defaults.string(forKey: Self.currentKey),
              accounts.contains(where: { $0.userID == id })
        else { return nil }
        return UserScope(id: id)
    }

    public var currentAccount: Account? {
        guard let scope = currentScope else { return nil }
        return accounts.first { $0.userID == scope.id }
    }

    /// Records a signed-in account and makes it current.
    public func add(_ account: Account, session: AuthSession) throws {
        try keychain(for: account.userID).save(session)

        var roster = accounts.filter { $0.userID != account.userID }
        roster.append(account)
        write(roster)
        defaults.set(account.userID, forKey: Self.currentKey)
    }

    /// Switches without asking anyone to sign in again.
    ///
    /// Refuses an account with no stored session rather than switching to one
    /// that cannot sync: landing on a signed-out shell that looks signed in is
    /// worse than staying put.
    @discardableResult
    public func setCurrent(_ userID: String) -> Bool {
        guard accounts.contains(where: { $0.userID == userID }),
              keychain(for: userID).load() != nil
        else { return false }
        defaults.set(userID, forKey: Self.currentKey)
        return true
    }

    /// Signs one account out, leaving the others alone.
    ///
    /// The store file is deliberately left on disk. Signing out is not a
    /// request to delete a year of notes, and someone who signs back in
    /// expects to find them; removing the account from the device is a
    /// different, louder action.
    public func remove(_ userID: String) {
        keychain(for: userID).clear()
        write(accounts.filter { $0.userID != userID })
        if defaults.string(forKey: Self.currentKey) == userID {
            defaults.removeObject(forKey: Self.currentKey)
        }
    }

    // MARK: - Sessions

    public func session(for userID: String) -> AuthSession? {
        keychain(for: userID).load()
    }

    public func sessionStore(for userID: String) -> any AuthSessionStoring {
        keychain(for: userID)
    }

    /// The store for whoever is current, or nil when nobody is.
    public func currentSessionStore() -> (any AuthSessionStoring)? {
        currentScope.map { keychain(for: $0.id) }
    }

    private func keychain(for userID: String) -> any AuthSessionStoring {
        sessionStores(userID)
    }

    private func write(_ roster: [Account]) {
        guard let data = try? JSONEncoder().encode(roster) else { return }
        defaults.set(data, forKey: Self.rosterKey)
    }
}
