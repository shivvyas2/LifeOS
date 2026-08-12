import SwiftUI
import DesignSystem
import OSLog

private let shellLog = Logger(subsystem: "shivvyas.LIfeOS", category: "shell")

/// Decides between onboarding and the app.
///
/// Signup is required, so this is the only entry point. It is a separate view
/// from `RootView` so the tab hierarchy is never constructed for a signed-out
/// user — a half-built RootView reading an empty store was the alternative.
struct AppShell: View {
    @State private var onboarding = OnboardingViewModel()
    @State private var whoop = WhoopConnectionViewModel()
    /// Persisted: finishing onboarding is a fact about the user, not about this
    /// launch. Without this, any relaunch that cannot restore a Supabase session
    /// re-runs the intro flow instead of opening Today.
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    /// TEMPORARY: set by "Skip for now". Deliberately not persisted, so a
    /// relaunch returns to signup and the bypass cannot quietly become the
    /// default state of the app.
    @State private var isGuest = false
    @Environment(\.modelContext) private var context

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
