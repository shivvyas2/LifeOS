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
    @AppStorage("colorSchemePreference") private var appearance: ColorSchemePreference = .system
    @Environment(\.scenePhase) private var scenePhase
    /// TEMPORARY: set by "Skip for now". Deliberately not persisted, so a
    /// relaunch returns to signup and the bypass cannot quietly become the
    /// default state of the app.
    @State private var isGuest = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if (onboarding.isSignedIn && hasFinishedOnboarding) || isGuest {
                RootView(whoop: whoop, onSignOut: {
                    isGuest = false
                    hasFinishedOnboarding = false
                    onboarding.signOut()
                })
            } else {
                OnboardingFlow(
                    model: onboarding,
                    whoop: whoop,
                    onFinish: { withAnimation(.easeInOut(duration: 0.35)) { hasFinishedOnboarding = true } },
                    onSkipAuth: { withAnimation(.easeInOut(duration: 0.35)) { isGuest = true } }
                )
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            whoop.attach(context)
            // A returning user has a session already; renew it and skip past
            // signup rather than making them prove themselves on every launch.
            if await onboarding.restoreSession() { hasFinishedOnboarding = true }
            await whoop.syncIfStale()
        }
        // Nothing awaits the sync: screens render local data immediately and
        // repaint through the ModelContext.didSave reload when it lands. The
        // launch task above and this transition fire together on a cold start;
        // the view model coalesces them into one sync.
        //
        // An access token lasts an hour, so a session that was fine when the app
        // went into the background is often stale by the time it comes back.
        // Renewing first keeps the sync that follows it authorised; concurrent
        // calls are coalesced inside each view model.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                // Renewal only, deliberately one-directional. Whether onboarding
                // is done was decided at launch; promoting here as well would
                // yank a user straight out of the profile step the moment they
                // switched apps after entering their code. Demotion still
                // applies: a refused session must not leave a shell behind that
                // can no longer sync.
                if await onboarding.restoreSession() == false, !isGuest {
                    hasFinishedOnboarding = false
                }
                await whoop.syncIfStale()
            }
        }
        .onOpenURL { url in
            // Logged at the door: if nothing appears here, the redirect never
            // reached the app at all and the problem is upstream of our code.
            // Only Whoop uses the scheme now that email is a code, not a link.
            shellLog.info("opened url host=\(url.host ?? "?", privacy: .public)")
            whoop.handleCallback(url)
        }
    }
}
