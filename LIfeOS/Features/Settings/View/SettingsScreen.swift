import SwiftUI
import DesignSystem

struct SettingsScreen: View {
    @Bindable var model: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    @AppStorage("colorSchemePreference") private var appearance: ColorSchemePreference = .system
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GradientCanvas(hue: .habits) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Appearance")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

                        SoftCard {
                            SegmentedPill(
                                selection: $appearance,
                                options: ColorSchemePreference.allCases.map { ($0, $0.title) }
                            )
                        }

                        Text("Daily goals")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

                        SoftCard {
                            VStack(spacing: 14) {
                                stepper("Steps", value: "\(model.draft.steps)") {
                                    Stepper("", value: $model.draft.steps, in: 1000...30000, step: 500)
                                        .labelsHidden()
                                }
                                stepper("Sleep",
                                        value: "\(model.draft.sleepMinutes / 60)h \(model.draft.sleepMinutes % 60)m") {
                                    Stepper("", value: $model.draft.sleepMinutes, in: 240...660, step: 15)
                                        .labelsHidden()
                                }
                                stepper("Exercise", value: "\(model.draft.exerciseMinutes) min") {
                                    Stepper("", value: $model.draft.exerciseMinutes, in: 5...180, step: 5)
                                        .labelsHidden()
                                }
                                stepper("Water", value: "\(Int(model.draft.waterML)) ml") {
                                    Stepper("", value: $model.draft.waterML, in: 500...6000, step: 250)
                                        .labelsHidden()
                                }
                                stepper("Good day", value: "\(model.draft.requiredCount) of 4") {
                                    Stepper("", value: $model.draft.requiredCount, in: 1...4)
                                        .labelsHidden()
                                }
                            }
                        }

                        Text("Connections")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .padding(.top, 6)

                        if let whoop {
                            NavigationLink {
                                ConnectionsSettingsScreen(whoop: whoop)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Whoop, Health, banks")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                        Text(whoop.statusDetail)
                                            .font(.system(size: 13))
                                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5),
                                                              lineWidth: 1)
                                        }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                }
            }
        }
        .onChange(of: model.draft) { model.save() }
    }

    private func stepper<Control: View>(_ label: String, value: String,
                                        @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            control()
        }
    }
}

#Preview {
    SettingsScreen(model: SettingsViewModel())
}
