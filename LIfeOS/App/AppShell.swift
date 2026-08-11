import SwiftUI
import DesignSystem

/// Decides between onboarding and the app.
///
/// Signup is required, so this is the only entry point. It is a separate view
/// from `RootView` so the tab hierarchy is never constructed for a signed-out
/// user — a half-built RootView reading an empty store was the alternative.
struct AppShell: View {
    @State private var onboarding = OnboardingViewModel()
    @State private var whoop = WhoopConnectionViewModel()
    @State private var hasFinishedOnboarding = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if onboarding.isSignedIn && hasFinishedOnboarding {
                RootView(whoop: whoop)
            } else {
                OnboardingFlow(model: onboarding, whoop: whoop) {
                    withAnimation(.easeInOut(duration: 0.35)) { hasFinishedOnboarding = true }
                }
            }
        }
        .task {
            whoop.attach(context)
            // A returning user has a session already; skip straight past signup
            // rather than making them prove themselves again on every launch.
            if onboarding.isSignedIn { hasFinishedOnboarding = true }
        }
        .onOpenURL { url in whoop.handleCallback(url) }
    }
}
