import Testing
import Foundation
import Integrations
@testable import AccountUI

final class FailingStore: AuthSessionStoring, @unchecked Sendable {
    func load() -> AuthSession? { nil }
    func save(_ session: AuthSession) throws { throw AuthStoreError.keychain(-34018) }
    func clear() {}
}

@MainActor
struct AccountGateTests {
    @Test func verifyingPersistsTheSessionAndSignsIn() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let store = InMemoryAuthSessionStore()
        let gate = AccountGate(backend: backend, store: store)
        gate.signIn.draft.code = "123456"
        await gate.signIn.verifyCode()
        #expect(gate.isSignedIn)
        #expect(store.load()?.userID == "u1")
    }

    @Test func aSessionThatCannotBeSavedStaysSignedOut() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let gate = AccountGate(backend: backend, store: FailingStore())
        gate.signIn.draft.code = "123456"
        await gate.signIn.verifyCode()
        #expect(!gate.isSignedIn)
        #expect(gate.signIn.errorMessage != nil)
    }

    @Test func restoreKeepsAnActiveSession() async {
        let backend = FakeBackend()
        backend.restoreOutcome = .active(.sample())
        let gate = AccountGate(backend: backend, store: InMemoryAuthSessionStore())
        await gate.restore()
        #expect(gate.session?.userID == "u1")
    }

    @Test func aRefusedSessionSignsOutWithAMessage() async {
        let backend = FakeBackend()
        backend.restoreOutcome = .rejected
        let store = InMemoryAuthSessionStore(session: .sample())
        let gate = AccountGate(backend: backend, store: store)
        await gate.restore()
        #expect(!gate.isSignedIn)
        #expect(store.load() == nil)
        #expect(gate.signIn.errorMessage == "Your session expired. Sign in again")
    }

    @Test func signOutStartsAFreshSignIn() async {
        let backend = FakeBackend()
        backend.verifyResult = .success(.sample())
        let store = InMemoryAuthSessionStore()
        let gate = AccountGate(backend: backend, store: store)
        gate.signIn.draft.code = "123456"
        await gate.signIn.verifyCode()
        gate.signOut()
        #expect(!gate.isSignedIn)
        #expect(store.load() == nil)
        #expect(gate.signIn.step == .identity)
        #expect(gate.signIn.draft.code.isEmpty)
    }

    /// Launch and the first `.active` both restore. Two refreshes with one
    /// refresh token would make the loser report the store changed under it;
    /// one restore must serve both callers.
    @Test func concurrentRestoresShareOneRefresh() async {
        let backend = FakeBackend()
        backend.restoreOutcome = .active(.sample())
        backend.restoreDelay = .milliseconds(50)
        let gate = AccountGate(backend: backend, store: InMemoryAuthSessionStore(session: .sample()))
        async let first: Void = gate.restore()
        async let second: Void = gate.restore()
        _ = await (first, second)
        #expect(backend.restoreCalls == 1)
        #expect(gate.isSignedIn)
    }

    /// `.signedOut` from the refresher can mean "the store changed under me"
    /// (another refresh won). The gate follows the store, not the verdict.
    @Test func signedOutFollowsWhatTheStoreHolds() async {
        let backend = FakeBackend()
        backend.restoreOutcome = .signedOut
        let gate = AccountGate(backend: backend, store: InMemoryAuthSessionStore(session: .sample()))
        await gate.restore()
        #expect(gate.isSignedIn)
    }
}
