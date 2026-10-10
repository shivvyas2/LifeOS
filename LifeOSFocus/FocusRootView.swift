import SwiftUI
import AccountUI
import Integrations

/// Sign-in until there is a session, then Home. The session is restored on
/// launch and on every return to the foreground, the same rule LifeOS uses.
struct FocusRootView: View {
    @State private var gate = AccountGate(backend: FocusConfig.auth, store: KeychainAuthSessionStore())
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if gate.isSignedIn {
                FocusHomeView(gate: gate)
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
    }
}
