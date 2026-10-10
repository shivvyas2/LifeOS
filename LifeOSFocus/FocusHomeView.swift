import SwiftUI
import AccountUI
import DesignSystem

/// The starter Home. The moods, Resume last and recent sessions arrive with
/// the Focus code in the next slice; this proves the account end to end.
struct FocusHomeView: View {
    let gate: AccountGate
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "LifeOS Focus", title: "Focus",
                                  detail: "Signed in as \(account).")
                Text("Your sessions will start here.")
                    .font(LifeOSType.body)
                    .foregroundStyle(Editorial.quietInk(scheme))
                Button("Sign out") { gate.signOut() }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }

    private var account: String {
        gate.session?.email ?? gate.session?.phone ?? "your account"
    }
}
