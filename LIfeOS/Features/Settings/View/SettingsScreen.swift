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

    /// A page of its own, pushed from the profile's gear. No inner
    /// NavigationStack and no Done: the back chevron is the way out, which is
    /// what makes this feel like a place rather than an overlay.
    var body: some View {
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
        .onChange(of: model.draft) { model.save() }
    }

    @ViewBuilder
    private var sections: some View {
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

    /// Three services, three rows, each showing its own state.
    ///
    /// This used to be a single row with a chain-link icon reading "Whoop,
    /// Health, banks" over Whoop's status line, which said nothing about the
    /// other two: a connected bank and a broken Health permission looked
    /// identical from here, and the subtitle actively misreported them. The
    /// point of a settings summary is to answer "is everything on?" without
    /// opening anything, so it has to show all three.
    @ViewBuilder
    private var connectionsRow: some View {
        if let whoop, let health, let plaid {
            NavigationLink {
                ConnectionsSettingsScreen(whoop: whoop, health: health, plaid: plaid)
            } label: {
                VStack(spacing: 0) {
                    connectionLine(
                        icon: "bolt.heart.fill", name: "Whoop",
                        detail: whoop.statusDetail, isOn: whoop.isConnected,
                        isBusy: whoop.isSyncing
                    )
                    rowDivider
                    connectionLine(
                        icon: "heart.fill", name: "Apple Health",
                        detail: health.statusDetail, isOn: health.isConnected
                    )
                    rowDivider
                    connectionLine(
                        // The same words the Connections screen uses. Two
                        // names for one thing makes a reader wonder whether
                        // they are two things.
                        icon: "building.columns.fill", name: "Bank accounts",
                        detail: plaid.statusDetail, isOn: plaid.isConnected,
                        showsChevron: true
                    )
                }
                .padding(.vertical, 4)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 62)
    }

    /// One service. The dot is the answer at a glance; the sentence under the
    /// name is the detail for when the dot is not enough.
    private func connectionLine(
        icon: String, name: String, detail: String,
        isOn: Bool, isBusy: Bool = false, showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(LifeOSType.label.weight(.semibold))
                .foregroundStyle(isOn ? LifeOSTokens.accent
                                      : LifeOSTokens.secondaryText.resolve(scheme))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(isOn ? LifeOSTokens.accentSoft.resolve(scheme)
                                       : LifeOSTokens.cardSurface.resolve(scheme))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                Text(detail)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Green for on, hollow for off. Never red: not being connected is
            // a choice someone is allowed to make, and an alarm dot next to
            // Whoop would nag every user who does not own one.
            if isBusy {
                // The dot answers "is it on"; while a sync is running the
                // honest answer is "ask me in a second", so the spinner takes
                // its place rather than sitting beside it.
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(isOn ? Color(red: 0.20, green: 0.70, blue: 0.42) : .clear)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if !isOn {
                            Circle().strokeBorder(
                                LifeOSTokens.secondaryText.resolve(scheme).opacity(0.4),
                                lineWidth: 1
                            )
                        }
                    }
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            } else {
                // Keeps the three rows' text columns aligned: without it the
                // chevron on the last row would shift only that row's dot.
                Color.clear.frame(width: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
    NavigationStack {
        SettingsScreen(model: SettingsViewModel())
    }
}
