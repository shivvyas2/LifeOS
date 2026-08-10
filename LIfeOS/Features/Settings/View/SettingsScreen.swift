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
                Button("Connect Whoop") { model.connect() }
            case .connecting:
                ProgressView()
            case .connected:
                HStack(spacing: 16) {
                    Button("Sync now") { Task { await model.sync() } }
                    Button("Disconnect", role: .destructive) { model.disconnect() }
                }
            }
        }
    }
}

#Preview {
    SettingsScreen(model: SettingsViewModel())
}
