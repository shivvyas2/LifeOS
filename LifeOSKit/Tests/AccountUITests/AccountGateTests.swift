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
}
