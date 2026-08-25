import SwiftUI
import DesignSystem
import OSLog

private let shellLog = Logger(subsystem: "com.shivvyas.lifeos", category: "shell")

/// Decides between onboarding and the app.
///
/// Signup is required, so this is the only entry point. It is a separate view
/// from `RootView` so the tab hierarchy is never constructed for a signed-out
/// user. A half-built RootView reading an empty store was the alternative.
struct AppShell: View {
    @State private var onboarding = OnboardingViewModel()
    @State private var whoop = WhoopConnectionViewModel()
    /// Persisted, but the win is narrower than the name suggests: `isSignedIn`
    /// resolves synchronously (a keychain read), so on a relaunch that restores
    /// a session this flag is already true on the first render, instead of
    /// flashing the intro carousel for a frame before `.task` below sets it.
    /// It buys nothing when the session cannot be restored — `isSignedIn` is
    /// false there, so the gate below sends the user through onboarding
    /// regardless of this flag.
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    /// TEMPORARY: set by "Skip for now". Deliberately not persisted, so a
    /// relaunch returns to signup and the bypass cannot quietly become the
    /// default state of the app.
    @State private var isGuest = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if (onboarding.isSignedIn && hasFinishedOnboarding) || isGuest {
                RootView(whoop: whoop)
            } else {
                OnboardingFlow(
                    model: onboarding,
                    whoop: whoop,
                    onFinish: { withAnimation(.easeInOut(duration: 0.35)) { hasFinishedOnboarding = true } },
                    onSkipAuth: { withAnimation(.easeInOut(duration: 0.35)) { isGuest = true } }
                )
            }
        }
        .task {
            whoop.attach(context)
            // A returning user has a session already; skip straight past signup
            // rather than making them prove themselves again on every launch.
            if onboarding.isSignedIn { hasFinishedOnboarding = true }
            await whoop.syncIfStale()
        }
        // Nothing awaits the sync: screens render local data immediately and
        // repaint through the ModelContext.didSave reload when it lands. The
        // launch task above and this transition fire together on a cold start;
        // the view model coalesces them into one sync.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await whoop.syncIfStale() }
        }
        .onOpenURL { url in
            // Two callbacks share the scheme; the host decides which owns it.
            // Logged at the door: if nothing appears here, the redirect never
            // reached the app at all and the problem is upstream of our code.
            shellLog.info("opened url host=\(url.host ?? "?", privacy: .public)")
            if url.host == "auth-callback" {
                onboarding.handleAuthCallback(url)
            } else {
                whoop.handleCallback(url)
            }
        }
    }
}
