import SwiftUI
import DesignSystem

struct SettingsScreen: View {
    @Bindable var model: SettingsViewModel
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
                    ForEach(model.connections) { connection in
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

#Preview {
    SettingsScreen(model: SettingsViewModel())
}
