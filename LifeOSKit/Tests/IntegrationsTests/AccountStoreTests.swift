import Testing
import Foundation
import Persistence
@testable import Integrations

@Suite @MainActor struct AccountStoreTests {

    /// One in-memory session store per account, kept across calls so the store
    /// behaves like a keychain that remembers.
    private final class Keyring {
        var stores: [String: InMemoryAuthSessionStore] = [:]
        func store(_ userID: String) -> any AuthSessionStoring {
            if let existing = stores[userID] { return existing }
            let made = InMemoryAuthSessionStore()
            stores[userID] = made
            return made
        }
    }

    private func makeStore() -> (AccountStore, Keyring, UserDefaults) {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let keyring = Keyring()
        return (AccountStore(defaults: suite, sessionStores: { keyring.store($0) }), keyring, suite)
    }

    private func session(_ userID: String) -> AuthSession {
        AuthSession(
            accessToken: "access-\(userID)", refreshToken: "refresh-\(userID)",
            expiresAt: .now.addingTimeInterval(3600), userID: userID,
            phone: nil, email: "\(userID)@example.com", hasProfile: true
        )
    }

    @Test func nobodySignedInMeansNoScope() {
        let (store, _, _) = makeStore()
        #expect(store.currentScope == nil)
        #expect(store.accounts.isEmpty)
    }

    /// The bug this whole type exists to fix: a second sign-in used to
    /// overwrite the first, with no way back.
    @Test func aSecondAccountDoesNotEvictTheFirst() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "alice@example.com"), session: session("alice"))
        try store.add(Account(userID: "bob", label: "bob@example.com"), session: session("bob"))

        #expect(store.accounts.map(\.userID).sorted() == ["alice", "bob"])
        #expect(store.session(for: "alice")?.accessToken == "access-alice")
        #expect(store.session(for: "bob")?.accessToken == "access-bob")
    }

    @Test func theNewestSignInBecomesCurrent() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))
        try store.add(Account(userID: "bob", label: "b"), session: session("bob"))

        #expect(store.currentScope == UserScope(id: "bob"))
    }

    @Test func switchingNeedsNoSecondSignIn() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))
        try store.add(Account(userID: "bob", label: "b"), session: session("bob"))

        #expect(store.setCurrent("alice"))
        #expect(store.currentScope == UserScope(id: "alice"))
        #expect(store.currentAccount?.label == "a")
    }

    /// Landing on a signed-out shell that looks signed in is worse than
    /// staying put.
    @Test func switchingToAnAccountWithNoSessionIsRefused() throws {
        let (store, keyring, _) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))
        try store.add(Account(userID: "bob", label: "b"), session: session("bob"))
        keyring.stores["alice"]?.clear()

        #expect(store.setCurrent("alice") == false)
        #expect(store.currentScope == UserScope(id: "bob"))
    }

    @Test func switchingToAnUnknownAccountIsRefused() {
        let (store, _, _) = makeStore()
        #expect(store.setCurrent("nobody") == false)
    }

    /// Signing one account out must not touch the others.
    @Test func removingOneAccountLeavesTheRest() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))
        try store.add(Account(userID: "bob", label: "b"), session: session("bob"))

        store.remove("bob")

        #expect(store.accounts.map(\.userID) == ["alice"])
        #expect(store.session(for: "bob") == nil)
        #expect(store.session(for: "alice") != nil)
    }

    /// Removing the current account signs the device out rather than silently
    /// opening whoever happens to be left.
    @Test func removingTheCurrentAccountDoesNotOpenSomeoneElse() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))
        try store.add(Account(userID: "bob", label: "b"), session: session("bob"))

        store.remove("bob")

        #expect(store.currentScope == nil)
    }

    /// A stale current id must never resolve to another person's store.
    @Test func aCurrentIdNamingNoKnownAccountResolvesToNobody() throws {
        let (store, _, suite) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))
        suite.set("ghost", forKey: "accounts.current")

        #expect(store.currentScope == nil)
    }

    @Test func signingInAgainAsTheSameAccountRefreshesRatherThanDuplicates() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "old@example.com"), session: session("alice"))
        try store.add(Account(userID: "alice", label: "new@example.com"), session: session("alice"))

        #expect(store.accounts.count == 1)
        #expect(store.currentAccount?.label == "new@example.com")
    }

    /// Signing out is not a request to delete a year of notes: the account is
    /// forgotten, its store is not.
    @Test func removingAnAccountLeavesItsStoreOnDisk() throws {
        let (store, _, _) = makeStore()
        try store.add(Account(userID: "alice", label: "a"), session: session("alice"))

        store.remove("alice")

        #expect(store.accounts.isEmpty)
        #expect(store.currentScope == nil)
    }
}
