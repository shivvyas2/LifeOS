import SwiftUI
import AccountUI
import Integrations

/// Sign-in until there is a session, then Home. The session is restored on
/// launch and on every return to the foreground, the same rule LifeOS uses.
/// Each account gets its own `FocusSession`, built when the account changes.
struct FocusRootView: View {
    @State private var gate = AccountGate(backend: FocusConfig.auth, store: KeychainAuthSessionStore())
    @State private var focus: FocusSession?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if gate.isSignedIn, let focus {
                FocusHomeView(gate: gate, session: focus)
            } else if gate.isSignedIn {
                ProgressView()
            } else if gate.signIn.step == .code {
                CodeScreen(model: gate.signIn, totalSteps: 2, onBack: { _ = gate.signIn.back() })
            } else {
                IdentityScreen(model: gate.signIn, totalSteps: 2, onBack: { _ = gate.signIn.back() })
            }
        }
        .animation(.easeInOut(duration: 0.28), value: gate.isSignedIn)
        .task { await gate.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await gate.restore() } }
        }
        // A different account, or none: the old one's session is ended and
        // its sound and bells stopped before anything else is shown.
        .onChange(of: gate.session?.userID, initial: true) { _, owner in
            guard focus?.owner != owner else { return }
            focus?.close()
            focus = owner.map { FocusSession(owner: $0) }
        }
    }
}
