import SwiftUI
import Integrations

@main
struct LifeOSFocusApp: App {
    init() {
        // The group LifeOS and its companion apps share for "Continue as".
        // Only an access token is ever left there; see `SharedSignIn`.
        SharedSignIn.accessGroup = "Z42YU5W6WY.com.shivvyas.lifeos.shared"
    }

    var body: some Scene {
        WindowGroup { FocusRootView() }
    }
}
