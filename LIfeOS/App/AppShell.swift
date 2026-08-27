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
    @State private var health = HealthConnectionViewModel()
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
    /// Set by "Skip for now", and now persisted, because signing in is no
    /// longer required to reach the app: a launch that restores no session
    /// lands on the app rather than on signup. Persisting it is what stops the
    /// intro reappearing on every cold start for someone who never intends to
    /// sign in.
    ///
    /// Signing in is still reachable, through Settings, and is still what a
    /// user needs before anything server-backed works: bank connection and the
    /// coach's cloud tier both authenticate with a real session, so a guest
    /// gets the local app and is told as much at the point those fail.
    @AppStorage("isGuest") private var isGuest = false
    /// The one-time walkthrough. Keyed on its own flag rather than on
    /// `hasFinishedOnboarding`, so it fires exactly once per install however
    /// the person arrived: signup, sign-in, or skip.
    @AppStorage("hasSeenFirstRunTour") private var hasSeenFirstRunTour = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if (onboarding.isSignedIn && hasFinishedOnboarding) || isGuest {
                RootView(whoop: whoop, health: health, onSignOut: {
                    isGuest = false
                    hasFinishedOnboarding = false
                    onboarding.signOut()
                })
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenFirstRunTour },
                    set: { hasSeenFirstRunTour = !$0 }
                )) {
                    FirstRunTour { hasSeenFirstRunTour = true }
                }
            } else {
                OnboardingFlow(
                    model: onboarding,
                    whoop: whoop,
                    health: health,
                    onFinish: { withAnimation(.easeInOut(duration: 0.35)) { hasFinishedOnboarding = true } },
                    onSkipAuth: { withAnimation(.easeInOut(duration: 0.35)) { isGuest = true } }
                )
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            whoop.attach(context)
            health.attach(context)
            // A returning user has a session already; renew it and skip past
            // signup rather than making them prove themselves on every launch.
            if await onboarding.restoreSession() {
                hasFinishedOnboarding = true
            } else {
                // No session, so open the app anyway rather than holding the
                // door shut. Signing in is a thing this app offers, not a
                // toll it charges: everything local works without an account,
                // and the parts that cannot say so where they fail.
                //
                // This is what makes the intro reachable only through Settings
                // -> Sign out. Restoring the old behaviour is deleting this
                // else branch, which puts a signed-out launch back on signup.
                isGuest = true
            }
            await whoop.syncIfStale()
            // After Whoop, not before: Health fills the gaps Whoop leaves, so
            // running it second means it sees the strap's numbers already in
            // place and writes only where they are missing.
            await health.syncIfConnected()
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
                // Before syncing: a sign-in abandoned in Safari leaves the
                // card spinning, and coming back is the only moment we learn
                // it was abandoned.
                await whoop.resolveStalledConnect()
                await whoop.syncIfStale()
                await health.syncIfConnected()
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
