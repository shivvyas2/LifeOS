import SwiftUI
import Integrations
import AccountUI

@main
struct LifeOSFocusApp: App {
    init() {
        // The group LifeOS and its companion apps share for "Continue as".
        // Only an access token is ever left there; see `SharedSignIn`.
        SharedSignIn.accessGroup = "Z42YU5W6WY.com.shivvyas.lifeos.shared"
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--design-preview") {
                PreviewHome()
            } else {
                FocusRootView()
            }
            #else
            FocusRootView()
            #endif
        }
    }
}

#if DEBUG
/// Home signed in as a sample account over an in-memory store, for
/// screenshots: `--design-preview`. Nothing here reaches the network.
private struct PreviewHome: View {
    @State private var gate = AccountGate(backend: nil, store: InMemoryAuthSessionStore(session: AuthSession(
        accessToken: "preview", refreshToken: nil, expiresAt: .distantFuture, userID: "preview",
        phone: nil, email: "preview@lifeos.app", hasProfile: true)))
    @State private var session = FocusSession(owner: "preview", inMemory: true)

    var body: some View { FocusHomeView(gate: gate, session: session) }
}
#endif
