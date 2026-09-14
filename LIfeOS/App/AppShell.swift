import SwiftUI
import AppSurfaces
import Integrations
import Persistence
import DesignSystem
import OSLog

private let shellLog = Logger(subsystem: "com.shivvyas.lifeos", category: "shell")

/// Decides between onboarding and the app.
///
/// Signup is required, so this is the only entry point. It is a separate view
/// from `RootView` so the tab hierarchy is never constructed for a signed-out
/// user. A half-built RootView reading an empty store was the alternative.
struct AppShell: View {
    /// Raised once a session exists, so the scene can record the account and
    /// open its store. The shell does not own the container: which account is
    /// open is a decision above it.
    var onSignedIn: (Account, AuthSession) -> Void = { _, _ in }
    var onSignedOut: () -> Void = {}
    /// Whether a store is actually open for this scene.
    ///
    /// The second lock, and the one that turns a bad state into a wrong screen
    /// rather than a dead process. A session alone is not enough to build the
    /// tab hierarchy: every screen below `RootView` reads through a
    /// `ModelContext`, and mounting it in a scene with no container gets as far
    /// as the first fetch before CoreData throws an `NSException` for an
    /// entity it cannot find in an empty schema. That is not catchable from
    /// Swift, so it is the whole process.
    var hasStore = false
    var accountID: String?

    @State private var onboarding = OnboardingViewModel()
    @State private var whoop = WhoopConnectionViewModel()
    @State private var fitbit = FitbitConnectionViewModel()
    @State private var health = HealthConnectionViewModel()
    @State private var plaid = PlaidConnectionViewModel()
    /// Persisted, but the win is narrower than the name suggests: `isSignedIn`
    /// resolves synchronously (a keychain read), so on a relaunch that restores
    /// a session this flag is already true on the first render, instead of
    /// flashing the intro carousel for a frame before `.task` below sets it.
    /// It buys nothing when the session cannot be restored — `isSignedIn` is
    /// false there, so the gate below sends the user through onboarding
    /// regardless of this flag.
    @AppStorage("hasFinishedOnboarding", store: .currentAccount) private var hasFinishedOnboarding = false
    @AppStorage("colorSchemePreference") private var appearance: ColorSchemePreference = .system
    @Environment(\.scenePhase) private var scenePhase
    /// The one-time walkthrough. Keyed on its own flag rather than on
    /// `hasFinishedOnboarding`, so it fires exactly once per account however
    /// the person arrived: signup, sign-in, or skip.
    @AppStorage("hasSeenFirstRunTour", store: .currentAccount) private var hasSeenFirstRunTour = false
    @State private var showTour = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if onboarding.isSignedIn && hasFinishedOnboarding && hasStore {
                RootView(whoop: whoop, fitbit: fitbit, plaid: plaid, health: health, onSignOut: {
                    // Before the session goes, not after: deleting this
                    // device's push row needs the access token of the account
                    // whose row it is. Left behind, that row would push one
                    // person's sleep data onto a phone now showing somebody
                    // else's name. The token is captured by value here, so the
                    // request still authenticates once the keychain is cleared
                    // a line later.
                    if let accessToken = KeychainAuthSessionStore().load()?.accessToken {
                        Task { await PushService.shared.deregister(accessToken: accessToken) }
                    }
                    whoop.deactivate()
                    fitbit.deactivate()
                    health.deactivate()
                    plaid.deactivate()
                    onboarding.signOut()
                })
                .overlay {
                    // An overlay, deliberately not a fullScreenCover: iOS can
                    // restore a previously-presented cover at launch, and two
                    // covers contending for the same window silently drops
                    // one. An overlay has no presentation machinery to lose.
                    if showTour {
                        FirstRunTour {
                            hasSeenFirstRunTour = true
                            withAnimation(.easeOut(duration: 0.3)) { showTour = false }
                        }
                        .transition(.opacity)
                    }
                }
                .task {
                    guard !hasSeenFirstRunTour, !showTour else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled && !hasSeenFirstRunTour {
                        withAnimation(.easeIn(duration: 0.25)) { showTour = true }
                    }
                }
            } else {
                OnboardingFlow(
                    model: onboarding,
                    whoop: whoop,
                    fitbit: fitbit,
                    plaid: plaid,
                    health: health,
                    onFinish: {
                        if let account = onboarding.account, let session = onboarding.session {
                            onSignedIn(account, session)
                        }
                        UserDefaults.currentAccount.removeObject(forKey: "onboarding.step")
                        withAnimation(.easeInOut(duration: 0.35)) { hasFinishedOnboarding = true }
                    },
                )
            }
        }
        .onChange(of: onboarding.session?.userID) { _, id in
            guard let id, (!hasStore || id != accountID), let account = onboarding.account, let session = onboarding.session else { return }
            onSignedIn(account, session)
        }
        .onChange(of: onboarding.isSignedIn) { wasSignedIn, signedIn in
            if wasSignedIn && !signedIn && hasStore { onSignedOut() }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            if hasStore {
                whoop.attach(context)
                health.attach(context)
                fitbit.attach(context)
                plaid.attach(context)
            }
            // A returning user has a session already; renew it and skip past
            // signup rather than making them prove themselves on every launch.
            // Only when there is somewhere for the restored account's data to
            // live. Without the second clause a session found in a scene with
            // no store promotes straight past the gate above.
            if await onboarding.restoreSession(), hasStore,
               onboarding.step == .signedIn {
                hasFinishedOnboarding = true
                // The profile belongs to the account, not to the phone that
                // typed it, so it is fetched rather than assumed present.
                await ProfileSync.pull()
            }
            // No session means signup, and that is now the only way in.
            //
            // The app used to open anyway on a signed-out launch, on the
            // reasoning that everything local worked without an account. It
            // does not any more: a store belongs to an account, notes sync to
            // one, and the connections are held per account. There is nowhere
            // for a signed-out person's data to live that would not become
            // somebody else's the moment they signed in.
            guard hasStore, onboarding.isSignedIn else { return }
            await whoop.syncIfStale()
            // After Whoop, not before: Health fills the gaps Whoop leaves, so
            // running it second means it sees the strap's numbers already in
            // place and writes only where they are missing.
            await health.syncIfConnected()
            await fitbit.syncIfDue()
            await plaid.syncIfDue()
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
        // Renews the session before it lapses, rather than only at launch and
        // on the way back from the background.
        //
        // An access token lives an hour. Somebody who keeps the app open for
        // longer than that used to pass the whole hour with neither of those
        // events firing, and every authenticated request from that point on
        // came back `HTTP 401: JWT expired` — friends would not load, the
        // coach reported it could not reach the cloud, notes stopped syncing.
        // Nothing was watching the clock.
        //
        // Keyed on the sign-in state so the loop starts the moment somebody
        // signs in and stops the moment they sign out, rather than waking on a
        // timer behind the signup screen.
        .task(id: onboarding.isSignedIn) {
            guard onboarding.isSignedIn else { return }
            while !Task.isCancelled {
                guard let expiresAt = KeychainAuthSessionStore().load()?.expiresAt else { return }
                try? await Task.sleep(for: .seconds(
                    SessionKeepAlive.delay(untilExpiry: expiresAt)
                ))
                guard !Task.isCancelled else { return }
                // Coalesced inside the view model with the launch and
                // foreground restores, so a wake that races one of those makes
                // one request rather than two. Supabase rotates the refresh
                // token on use, and two concurrent refreshes would have the
                // second present a token the first just retired.
                guard await onboarding.restoreSession() else { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                // Renewal only, deliberately one-directional. Whether onboarding
                // is done was decided at launch; promoting here as well would
                // yank a user straight out of the profile step the moment they
                // switched apps after entering their code. Demotion still
                // applies: a refused session must not leave a shell behind that
                // can no longer sync.
                if await onboarding.restoreSession() == false {
                    hasFinishedOnboarding = false
                }
                // Before syncing: a sign-in abandoned in Safari leaves the
                // card spinning, and coming back is the only moment we learn
                // it was abandoned.
                await whoop.resolveStalledConnect()
                guard hasStore, onboarding.isSignedIn else { return }
                await whoop.syncIfStale()
                await health.syncIfConnected()
                await fitbit.syncIfDue()
                await plaid.syncIfDue()
            }
        }
        .onOpenURL { url in
            // Logged at the door: if nothing appears here, the redirect never
            // reached the app at all and the problem is upstream of our code.
            shellLog.info("opened url host=\(url.host ?? "?", privacy: .public)")
            handle(url)
        }
        // A universal link does not always arrive as a plain URL. Plaid's OAuth
        // redirect is an https link on our own domain, and iOS is entitled to
        // deliver it as a browsing activity instead, so both doors are open.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            shellLog.info("continued activity host=\(url.host ?? "?", privacy: .public)")
            handle(url)
        }
    }

    /// One door for every link the app is handed.
    ///
    /// Plaid goes first: its redirect is the only one that can arrive while a
    /// half finished bank connection is waiting on it, and `resume` returns
    /// false for anything that is not that redirect, so Whoop loses nothing.
    private func handle(_ url: URL) {
        if let route = SurfaceRoute(url: url) {
            SurfaceCoordinator.shared.pendingRoute = route
            return
        }
        guard PlaidLinkPresenter.resume(from: url) == false else { return }
        if FitbitOAuth.state(in: url).map({ returned in
            KeychainFitbitAuthStore().pendingAuths().contains { $0.state == returned }
        }) == true {
            Task { await fitbit.handle(url) }
        } else {
            whoop.handleCallback(url)
        }
    }
}
