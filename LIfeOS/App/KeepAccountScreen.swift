import SwiftUI
import DesignSystem

/// Shown over everything when someone signs back in to an account set for
/// deletion: keep it, or sign out again.
struct KeepAccountScreen: View {
    let date: Date
    var onKeep: () async -> Void
    var onSignOut: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Spacer()
            EditorialMasthead(eyebrow: "Your account",
                              title: "Your account is set to be deleted on \(date.formatted(.dateTime.month(.wide).day())).",
                              detail: "Keep it and everything comes back as it was.")
            Button("Keep my account") {
                isWorking = true
                Task { await onKeep(); isWorking = false }
            }
            .buttonStyle(.editorial(.primary, fullWidth: true))
            .disabled(isWorking)
            Button("Sign out", action: onSignOut)
                .buttonStyle(.editorial(.quiet, fullWidth: true))
            Spacer()
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }
}
