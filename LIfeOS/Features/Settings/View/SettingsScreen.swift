import SwiftUI
import DesignSystem

struct SettingsScreen: View {
    @Bindable var model: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily goals") {
                    Stepper("Steps: \(model.draft.steps)",
                            value: $model.draft.steps, in: 1000...30000, step: 500)
                    Stepper("Sleep: \(model.draft.sleepMinutes / 60)h \(model.draft.sleepMinutes % 60)m",
                            value: $model.draft.sleepMinutes, in: 240...660, step: 15)
                    Stepper("Exercise: \(model.draft.exerciseMinutes) min",
                            value: $model.draft.exerciseMinutes, in: 5...180, step: 5)
                    Stepper("Water: \(Int(model.draft.waterML)) ml",
                            value: $model.draft.waterML, in: 500...6000, step: 250)
                    Stepper("Goals needed for a good day: \(model.draft.requiredCount) of 4",
                            value: $model.draft.requiredCount, in: 1...4)
                }

                Section("Connections") {
                    if let whoop {
                        WhoopConnectionRow(model: whoop)
                    }
                    ForEach(model.connections.filter { $0.id != "whoop" }) { connection in
                        LabeledContent(connection.name, value: connection.detail)
                    }
                }
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .navigationTitle("Settings")
        }
        // Commit on every change: a stepper has no natural "done", and the dot
        // grid should re-evaluate as soon as the rule moves.
        .onChange(of: model.draft) { model.save() }
    }
}

/// The Whoop row carries its own state because connecting is a round trip
/// through a web session, not a value edit.
private struct WhoopConnectionRow: View {
    @Bindable var model: WhoopConnectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Whoop", value: model.statusDetail)

            switch model.state {
            case .unconfigured:
                Text("Add SUPABASE_URL and deploy whoop-token to enable.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .disconnected, .failed:
                // Tinted explicitly: the section applies a muted foreground for
                // the static rows, which made this read as disabled text.
                Button("Connect Whoop") { model.connect() }
                    .font(.system(size: 15, weight: .semibold))
                    .tint(LifeOSTokens.accent)
                    .foregroundStyle(LifeOSTokens.accent)
                Button("Sign in on another device") { model.beginManual() }
                    .font(.system(size: 14))
                    .tint(LifeOSTokens.accent)
                    .foregroundStyle(LifeOSTokens.accent)
            case .connecting:
                if let url = model.manualURL {
                    manualSteps(url: url)
                } else {
                    ProgressView()
                }
            case .connected:
                HStack(spacing: 16) {
                    Button("Sync now") { Task { await model.sync() } }
                    Button("Disconnect", role: .destructive) { model.disconnect() }
                }
            }
        }
    }
}

private extension WhoopConnectionRow {
    /// Shown when Whoop's login will not complete in this device's browser.
    /// The code is transcribed from another device; the PKCE verifier stays
    /// here, so a code alone is not enough to connect.
    @ViewBuilder
    func manualSteps(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Open this link on a computer and sign in to Whoop.")
                .font(.system(size: 13))
            Button {
                UIPasteboard.general.string = url.absoluteString
            } label: {
                Label("Copy sign-in link", systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
            }
            .tint(LifeOSTokens.accent)
            .foregroundStyle(LifeOSTokens.accent)

            Text("2. Paste the code it shows you:")
                .font(.system(size: 13))
            TextField("Code", text: $model.manualCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14, design: .monospaced))

            HStack(spacing: 16) {
                Button("Connect") { Task { await model.submitManualCode() } }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(model.manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(LifeOSTokens.accent)
                Button("Cancel", role: .cancel) { model.cancelManual() }
                    .font(.system(size: 14))
            }
        }
        .padding(.top, 4)
    }
}

#Preview {
    SettingsScreen(model: SettingsViewModel())
}
