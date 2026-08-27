import SwiftUI
import DesignSystem

struct SettingsScreen: View {
    @Bindable var model: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    var health: HealthConnectionViewModel?
    var plaid: PlaidConnectionViewModel?
    var onSignOut: () -> Void = {}
    @AppStorage("colorSchemePreference") private var appearance: ColorSchemePreference = .system
    @AppStorage(MoneyViewModel.sampleDataKey) private var useSampleFinanceData = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GradientCanvas(hue: .habits) {
                ScrollView {
                    sections
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

    /// The settings themselves, without a screen around them.
    ///
    /// Pulled out so the profile screen can render exactly these rather than a
    /// second set that looks similar and drifts apart the first time either is
    /// touched. Settings now lives inside the profile; this screen stays
    /// because other places still push straight to it.
    @ViewBuilder
    var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionLabel("Look")
            appearanceCard

            sectionLabel("Daily goals")
            goalsCard

            sectionLabel("Connections")
            connectionsRow

            sectionLabel("Developer")
            sampleDataCard

            signOutButton
                .padding(.top, 8)
        }
    }

    /// Fills the Money screen with invented numbers so its layout can be judged
    /// while bank connection is broken. Ships in release builds, which is why
    /// the Money screen badges the month as sample: the toggle alone is not
    /// enough for a tester who flipped it once and opens the app a week later.
    private var sampleDataCard: some View {
        GlassPanel {
            Toggle(isOn: $useSampleFinanceData) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use sample finance data")
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text("Invented numbers, on by default so there is something to show. A connected bank replaces them, and the Money screen marks the month as sample while they show.")
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(LifeOSTokens.accent)
        }
    }

    private var appearanceCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                HStack(spacing: 10) {
                    ForEach(ColorSchemePreference.allCases, id: \.self) { option in
                        let selected = appearance == option
                        Button { appearance = option } label: {
                            VStack(spacing: 8) {
                                Image(systemName: Self.icon(for: option))
                                    .font(LifeOSType.body.weight(.semibold))
                                Text(option.title)
                                    .font(LifeOSType.caption.weight(.semibold))
                            }
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selected
                                          ? LifeOSTokens.cardSurface.resolve(scheme)
                                          : LifeOSTokens.primaryText.resolve(scheme).opacity(0.05))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(
                                                selected
                                                    ? ModuleHue.habits.top
                                                    : Color.clear,
                                                lineWidth: 2
                                            )
                                    }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var goalsCard: some View {
        GlassPanel {
            VStack(spacing: 0) {
                stepper(icon: "moon.fill", "Sleep",
                        value: "\(model.draft.sleepMinutes / 60)h \(model.draft.sleepMinutes % 60)m") {
                    Stepper("", value: $model.draft.sleepMinutes, in: 240...660, step: 15)
                        .labelsHidden()
                }
                divider
                stepper(icon: "figure.walk", "Steps", value: "\(model.draft.steps)") {
                    Stepper("", value: $model.draft.steps, in: 1000...30000, step: 500)
                        .labelsHidden()
                }
                divider
                stepper(icon: "figure.run", "Exercise", value: "\(model.draft.exerciseMinutes) min") {
                    Stepper("", value: $model.draft.exerciseMinutes, in: 5...180, step: 5)
                        .labelsHidden()
                }
                divider
                stepper(icon: "drop.fill", "Water", value: "\(Int(model.draft.waterML)) ml") {
                    Stepper("", value: $model.draft.waterML, in: 500...6000, step: 250)
                        .labelsHidden()
                }
                divider
                stepper(icon: "checkmark.circle.fill", "Good day",
                        value: "\(model.draft.requiredCount) of 4") {
                    Stepper("", value: $model.draft.requiredCount, in: 1...4)
                        .labelsHidden()
                }
            }
        }
    }

    @ViewBuilder
    private var connectionsRow: some View {
        if let whoop, let health, let plaid {
            NavigationLink {
                ConnectionsSettingsScreen(whoop: whoop, health: health, plaid: plaid)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "link")
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(LifeOSTokens.cardSurface.resolve(scheme)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Whoop, Health, banks")
                            .font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        Text(whoop.statusDetail)
                            .font(LifeOSType.label.weight(.regular))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(LifeOSType.label.weight(.semibold))
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

    private var signOutButton: some View {
        Button(role: .destructive) {
            onSignOut()
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(LifeOSType.rowTitle)
                Text("Log out")
                    .font(LifeOSType.rowTitle)
                Spacer()
            }
            .foregroundStyle(Color(red: 0.86, green: 0.22, blue: 0.22))
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(LifeOSType.label.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
    }

    private var divider: some View {
        Rectangle()
            .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private func stepper(icon: String, _ label: String, value: String,
                         @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(ModuleHue.habits.top)
                .frame(width: 28)
            Text(label)
                .font(LifeOSType.secondary.weight(.medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            Spacer()
            Text(value)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            control()
        }
    }

    private static func icon(for preference: ColorSchemePreference) -> String {
        switch preference {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }
}

#Preview {
    SettingsScreen(model: SettingsViewModel())
}
