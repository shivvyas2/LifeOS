import SwiftUI
import DesignSystem

/// Shown over everything when someone signs back in to an account set for
/// deletion: keep it, or sign out again.
struct KeepAccountScreen: View {
    let date: Date
    /// True when the server agreed.
    var onKeep: () async -> Bool
    var onSignOut: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Spacer()
            EditorialMasthead(eyebrow: "Your account",
                              title: "Your account is set to be deleted on \(date.formatted(.dateTime.month(.wide).day())).",
                              detail: "Keep it and everything comes back as it was.")
            Button("Keep my account") {
                isWorking = true
                failed = false
                Task { failed = !(await onKeep()); isWorking = false }
            }
            .buttonStyle(.editorial(.primary, fullWidth: true))
            .disabled(isWorking)
            if failed {
                Text("Could not reach the server. Your account is still set to be deleted.")
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button("Sign out", action: onSignOut)
                .buttonStyle(.editorial(.quiet, fullWidth: true))
            Spacer()
        }
        .padding(Space.x3)
        .accessibilityAddTraits(.isModal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }
}
