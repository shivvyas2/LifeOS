import SwiftUI
import Insights
import Persistence
import Integrations
import DesignSystem

struct SettingsScreen: View {
    /// The accounts signed in on this device. Held by the scene, because
    /// switching one replaces the store under everything below it.
    @Environment(\.accountSession) private var session

    @Bindable var model: SettingsViewModel
    var whoop: WhoopConnectionViewModel?
    var fitbit: FitbitConnectionViewModel?
    var health: HealthConnectionViewModel?
    var plaid: PlaidConnectionViewModel?
    var onSignOut: () -> Void = {}
    /// Both close Settings first; `RootView` acts once the cover has gone.
    var onReplayNotesWalkthrough: () -> Void = {}
    var onReplayTour: () -> Void = {}
    @AppStorage("colorSchemePreference") private var appearance: ColorSchemePreference = .system
    @AppStorage(TierPreference.storageKey) private var tierRaw = TierPreference.automatic.rawValue
    @AppStorage(AssistantVoice.enabledKey) private var speaksReplies = false
    @AppStorage(AssistantVoice.voiceKey) private var voiceRaw = AssistantVoice.default.rawValue
    @Environment(\.colorScheme) private var scheme

    /// A page of its own, pushed from the profile's gear. No inner
    /// NavigationStack and no Done: the back chevron is the way out, which is
    /// what makes this feel like a place rather than an overlay.
    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                sections
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
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
            AccountPageHeading(title: "Make it yours", detail: "Your preferences, daily goals and account.")
            sectionLabel("Appearance")
            appearanceCard

            sectionLabel("Daily goals")
            goalsCard

            if let session, session.signedInAccounts.count > 1 || session.currentAccount != nil {
                sectionLabel("Account")
                accountsCard(session)
            }

            sectionLabel("Your coach")
            tierCard

            sectionLabel("Voice")
            voiceCard

            sectionLabel("At a glance")
            AccountPanel {
                VStack(spacing: 18) {
                    NavigationLink { NotificationInboxScreen() } label: {
                        Label("Notifications", systemImage: "bell.badge").font(LifeOSType.rowTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    NavigationLink { SurfaceSettingsScreen() } label: {
                        Label("Widgets & Watch", systemImage: "applewatch").font(LifeOSType.rowTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    replayRow("Walk me through Notes again", systemImage: "hand.point.up.left", action: onReplayNotesWalkthrough)
                    Divider()
                    replayRow("Show the tour again", systemImage: "sparkles", action: onReplayTour)
                }
            }

            sectionLabel("Connections")
            connectionsRow

            sectionLabel("Your data")
            AccountPanel {
                VStack(spacing: 18) {
                    NavigationLink { ClearDataScreen() } label: {
                        Label("Clear data…", systemImage: "eraser").font(LifeOSType.rowTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    NavigationLink { DeleteAccountScreen(onDeleted: onSignOut) } label: {
                        Label("Delete account…", systemImage: "person.crop.circle.badge.xmark").font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            signOutButton
                .padding(.top, 8)
        }
    }

    /// Who is signed in, and who else could be.
    ///
    /// Switching does not sign anybody out. Each account keeps its own store,
    /// its own sync cursors and its own Whoop and bank connections, so moving
    /// between them is opening a different file rather than tearing one down.
    private func accountsCard(_ session: AccountSession) -> some View {
        AccountPanel {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(session.signedInAccounts) { account in
                    let current = account.userID == session.currentAccount?.userID
                    Button {
                        guard !current else { return }
                        session.switch(to: account.userID)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: current ? "checkmark.circle.fill" : "circle")
                                .font(LifeOSType.body)
                                .foregroundStyle(current
                                                 ? LifeOSTokens.accent
                                                 : LifeOSTokens.secondaryText.resolve(scheme))
                            Text(account.label)
                                .font(LifeOSType.rowTitle.weight(current ? .semibold : .regular))
                                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }

                Text("Each account keeps its own notes, health data and connections. Switching does not sign the others out.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Which engine answers.
    ///
    /// Offered because the two are genuinely different trades rather than
    /// better and worse: the cloud gives the stronger answer and spends an
    /// allowance, the phone gives a weaker one and sends nothing anywhere.
    /// Automatic is the default and the only one that falls back.
    private var tierCard: some View {
        AccountPanel {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(TierPreference.allCases) { option in
                    let selected = tierRaw == option.rawValue
                    Button { tierRaw = option.rawValue } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .font(LifeOSType.body)
                                .foregroundStyle(selected
                                                 ? LifeOSTokens.accent
                                                 : LifeOSTokens.secondaryText.resolve(scheme))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(LifeOSType.rowTitle.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                Text(option.detail)
                                    .font(LifeOSType.caption)
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
        }
    }

    /// Whether the coach speaks, and in which voice.
    ///
    /// Off by default. A coach that starts talking because an answer arrived,
    /// in a room the phone knows nothing about, is a worse default than
    /// silence. The voices are only offered once speech is on: three names
    /// that do nothing are three questions a person has to work out the
    /// answer to for no reason.
    private var voiceCard: some View {
        AccountPanel {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $speaksReplies) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speak replies")
                            .font(LifeOSType.rowTitle)
                        Text("Reads the coach's answers aloud.")
                            .font(LifeOSType.caption)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
                .tint(LifeOSTokens.accent)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

                if speaksReplies {
                    ForEach(AssistantVoice.allCases) { voice in
                        let selected = voiceRaw == voice.rawValue
                        Button { voiceRaw = voice.rawValue } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                    .font(LifeOSType.body)
                                    .foregroundStyle(selected
                                                     ? LifeOSTokens.accent
                                                     : LifeOSTokens.secondaryText.resolve(scheme))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(voice.title)
                                        .font(LifeOSType.rowTitle.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                    Text(voice.detail)
                                        .font(LifeOSType.caption)
                                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                    Text("\(VoiceBudget(defaults: .currentAccount).used().formatted()) of \(VoiceBudget.monthlyAllowance.formatted()) characters this month")
                        .font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var appearanceCard: some View {
        AccountPanel {
            VStack(alignment: .leading, spacing: 12) {
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
                                                    ? LifeOSTokens.accent
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
        AccountPanel {
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

    /// Every connected service, one row each, showing its own state.
    ///
    /// This used to be a single row with a chain-link icon reading "Whoop,
    /// Health, banks" over Whoop's status line, which said nothing about the
    /// other two: a connected bank and a broken Health permission looked
    /// identical from here, and the subtitle actively misreported them. The
    /// point of a settings summary is to answer "is everything on?" without
    /// opening anything, so it has to show every one of them.
    @ViewBuilder
    private var connectionsRow: some View {
        if let whoop, let fitbit, let health, let plaid {
            NavigationLink {
                ConnectionsSettingsScreen(whoop: whoop, fitbit: fitbit, health: health, plaid: plaid)
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
                    connectionLine(icon: "figure.run", name: "Fitbit", detail: fitbit.statusDetail,
                                   isOn: fitbit.isConnected, isBusy: fitbit.isSyncing)
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
            .font(LifeOSType.sectionTitle)
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
    }

    /// Drawn like the links above it, but closes Settings rather than pushing.
    private func replayRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(LifeOSType.rowTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
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
                .foregroundStyle(LifeOSTokens.accent)
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
