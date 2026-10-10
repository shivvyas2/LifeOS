import Foundation
import Observation
import Integrations

/// The signed-in session for an app that has one account at a time: restore
/// it on launch, keep it when sign-in succeeds, drop it on sign out.
///
/// `SignInModel` hands sessions over and never saves them, because LifeOS
/// files each account in its own Keychain slot. A companion app has one
/// slot, and this is what fills it.
@MainActor @Observable
public final class AccountGate {
    public private(set) var session: AuthSession?
    public private(set) var signIn: SignInModel

    private let backend: (any SignInBackend)?
    private let store: any AuthSessionStoring

    public init(backend: (any SignInBackend)?, store: any AuthSessionStoring) {
        self.backend = backend
        self.store = store
        self.session = store.load()
        // A placeholder so `self` is fully initialised before the real
        // model's closure captures it.
        self.signIn = SignInModel(backend: backend, store: store, onSignedIn: { _ in })
        self.signIn = makeSignIn()
    }

    public var isSignedIn: Bool { session != nil }

    /// Only a refusal from the server ends the session; being offline keeps
    /// it (see `SessionRefresher`).
    public func restore() async {
        guard let backend else { return }
        switch await backend.restore(store: store) {
        case .active(let refreshed):
            session = refreshed
        case .signedOut:
            session = nil
        case .rejected:
            signOut()
            signIn.report("Your session expired. Sign in again")
        }
    }

    public func signOut() {
        store.clear()
        session = nil
        signIn = makeSignIn()
    }

    private func makeSignIn() -> SignInModel {
        SignInModel(backend: backend, store: store) { [weak self] session in
            self?.keep(session)
        }
    }

    /// A session that cannot be stored is not a sign-in: the next launch
    /// would have nothing. Say so and stay on sign-in.
    private func keep(_ session: AuthSession) {
        do {
            try store.save(session)
            self.session = session
        } catch {
            signIn = makeSignIn()
            signIn.report("Couldn't save your sign-in on this device. Try again.")
        }
    }
}
