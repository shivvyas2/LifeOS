import SwiftUI
import DesignSystem
import Persistence
import Integrations

/// Schedules the account's deletion in 30 days. The phone signs out and keeps
/// this account's data until the deletion goes through, so signing back in
/// before the date brings everything back.
struct DeleteAccountScreen: View {
    var client: any AccountDataClienting = AccountDataClient()
    /// The shell's sign-out: push deregistered, connections stopped.
    var onDeleted: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.github) private var github
    @Environment(\.accountSession) private var session
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var failure: String?

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }
    private var date: Date { Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "Your data", title: "Delete account", detail: nil)
                VStack(alignment: .leading, spacing: Space.x2) {
                    line("Your account and everything stored for it is deleted on \(date.formatted(.dateTime.month(.wide).day())).")
                    line("Until then, signing back in with this number lets you keep it, with nothing lost.")
                    line("Groups you own pass to the member who has been in them longest.")
                    line("Connected services, your bank, Whoop, Fitbit and GitHub, are disconnected.")
                }
                HairlineField(text: $confirmation, placeholder: "Type DELETE to confirm", glyph: "exclamationmark.triangle",
                              submitLabel: .done)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Delete my account") { Task { await delete() } }
                    .buttonStyle(.editorial(.destructive, fullWidth: true))
                    .disabled(confirmation != "DELETE" || isWorking)
                if let failure {
                    Text(failure).font(LifeOSType.secondary).foregroundStyle(ink)
                }
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func line(_ text: String) -> some View {
        Text(text).font(LifeOSType.body).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
    }

    private func delete() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.scheduleDeletion()
        } catch {
            failure = "Could not schedule the deletion. Nothing has changed."
            return
        }
        // The GitHub token lives only on this phone, so it is revoked now.
        github?.disconnect()
        if let id = session?.currentAccount?.userID { PendingAccountWipe().add(id) }
        onDeleted()
    }
}
