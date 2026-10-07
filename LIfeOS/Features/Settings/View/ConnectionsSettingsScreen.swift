import SwiftUI
import DesignSystem
import Integrations

/// Account connections grouped by purpose, with a status and action for each source.
struct ConnectionsSettingsScreen: View {
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var fitbit: FitbitConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
    @Bindable var plaid: PlaidConnectionViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showWhoop = false
    @Environment(\.github) private var github

    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AccountPageHeading(title: "Better, connected", detail: "Your health and finances, together in Almanac.")
                    Label("Health & wearables", systemImage: "heart").font(LifeOSType.sectionTitle)
                    connectionCard(
                        icon: "bolt.heart.fill", hue: .recovery,
                        title: "WHOOP", status: whoop.statusDetail,
                        chip: whoopChip
                    ) { showWhoop = true }

                    connectionCard(
                        icon: "figure.run.circle.fill", hue: .body,
                        title: "Fitbit", status: fitbit.statusDetail,
                        chip: fitbitChip
                    ) {
                        if fitbit.isConnected { Task { await fitbit.syncIfDue(force: true) } }
                        else { fitbit.connect() }
                    }
                    .disabled(fitbit.state == .unconfigured || fitbit.isSyncing)

                    connectionCard(
                        icon: "heart.fill", hue: .body,
                        title: "Apple Health", status: health.statusDetail,
                        chip: healthChip
                    ) { Task { await health.connect() } }
                    .disabled(health.state == .unavailable)

                    if health.isConnected { cycleToggle }

                    Label("Finances", systemImage: "building.columns").font(LifeOSType.sectionTitle).padding(.top, 12)
                    connectionCard(
                        icon: "building.columns.fill", hue: .money,
                        title: "Bank accounts", status: plaid.statusDetail,
                        chip: bankChip
                    ) {
                        if case .connected = plaid.state {} else { plaid.connect() }
                    }
                    if let github {
                        Label("Work", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(LifeOSType.sectionTitle).padding(.top, 12)
                        connectionCard(
                            icon: "chevron.left.forwardslash.chevron.right", hue: .recovery,
                            title: "GitHub", status: github.statusDetail,
                            chip: githubChip(github)
                        ) {
                            if case .connected = github.state {} else { github.connect() }
                        }
                        .disabled(github.state == .unconfigured)
                        if case .connected = github.state { githubPin(github) }
                    }
                    Label("Connections stay with your account.", systemImage: "lock.shield")
                        .font(LifeOSType.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showWhoop {
                WhoopConnectModal(model: whoop) { showWhoop = false }
            }
        }
    }

    // MARK: - The one card

    private func connectionCard(
        icon: String, hue: ModuleHue,
        title: String, status: String,
        chip: Chip, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.title3)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .frame(width: 48, height: 48)
                        .background(scheme == .dark ? hue.pastelDark : hue.pastel, in: RoundedRectangle(cornerRadius: 16))
                    Text(title).font(LifeOSType.sectionTitle)
                    Spacer(minLength: 8)
                    Image(systemName: chip.standing ? "checkmark.circle.fill" : "arrow.up.right")
                        .foregroundStyle(LifeOSTokens.accent)
                }
                Text(status).font(LifeOSType.secondary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !chip.text.isEmpty {
                    HStack {
                        Text(chip.text == "…" ? "Connecting…" : chip.text).font(LifeOSType.rowTitle)
                        Spacer()
                        if chip.text == "…" { ProgressView() }
                    }
                    .foregroundStyle(chip.standing ? LifeOSTokens.primaryText.resolve(scheme) : LifeOSTokens.accent)
                }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    /// Offered to everyone, defaulted from Health's own sex characteristic.
    ///
    /// A switch rather than an inference, because who tracks a cycle is not
    /// answered by a profile field or by a characteristic: a trans man may
    /// track one and a woman past menopause may not want to. Defaulting it and
    /// then letting it be changed is the only arrangement that is right for
    /// both of them.
    private func githubChip(_ github: GitHubConnectionViewModel) -> Chip {
        switch github.state {
        // Once connected the card's tap does nothing; Disconnect sits below.
        case .connected: Chip(text: "", standing: true)
        case .connecting: Chip(text: "…")
        case .unconfigured: Chip(text: "Setup")
        default: Chip(text: "Connect")
        }
    }

    /// Which repo the day's card is about, and the way out.
    private func githubPin(_ github: GitHubConnectionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Pin a repo", selection: Binding(get: { github.pinnedRepo }, set: { github.pinnedRepo = $0 })) {
                Text("Automatic").tag(String?.none)
                ForEach(github.repos, id: \.fullName) { repo in
                    Text(repo.fullName).tag(String?.some(repo.fullName))
                }
            }
            .pickerStyle(.menu)
            .tint(LifeOSTokens.primaryText.resolve(scheme))
            .font(LifeOSType.rowTitle)
            if github.pinMissing {
                Text("Pinned repo not found")
                    .font(LifeOSType.caption)
                    .foregroundStyle(Editorial.quietInk(scheme))
            }
            Button("Disconnect") { github.disconnect() }
                .buttonStyle(.editorial(.destructive, size: .compact))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task { await github.loadRepos() }
    }

    private var cycleToggle: some View {
        Toggle(isOn: Binding(
            get: { health.readsCycleTracking },
            set: { enabled in Task { await health.setCycleTracking(enabled) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cycle tracking")
                    .font(LifeOSType.rowTitle)
                Text("Reads menstrual and cycle data from Health. Asks separately the first time.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(LifeOSTokens.accent)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// A verb in a soft capsule, or the standing state with a check. The
    /// difference in colour is the difference in meaning: orange asks for a
    /// tap, green reports one that already happened.
    private struct Chip {
        let text: String
        var standing = false
    }

    // MARK: - Per-source chips

    private var whoopChip: Chip {
        switch whoop.state {
        case .connected: Chip(text: "Sync")
        case .connecting: Chip(text: "…")
        case .unconfigured: Chip(text: "Setup")
        default: Chip(text: "Connect")
        }
    }

    private var fitbitChip: Chip {
        switch fitbit.state {
        case .connected: Chip(text: "Sync")
        case .connecting: Chip(text: "…")
        case .unconfigured: Chip(text: "Setup")
        // A dead credential is an action the user can take, not an error for
        // them to read, so the chip names the action.
        case .needsReauth: Chip(text: "Reconnect")
        default: Chip(text: "Connect")
        }
    }

    private var healthChip: Chip {
        switch health.state {
        case .unavailable: Chip(text: "")
        case .notAsked:    Chip(text: "Connect")
        case .syncing:     Chip(text: "…")
        // "Sync" rather than "Connect" once asked: iOS shows the permission
        // sheet exactly once, so offering to connect again would be a button
        // that visibly does nothing.
        case .synced, .noData, .failed: Chip(text: "Sync")
        }
    }

    private var bankChip: Chip {
        switch plaid.state {
        // The tap only connects, so the connected row shows a state, not a verb.
        case .connected: Chip(text: "Connected", standing: true)
        case .connecting: Chip(text: "…")
        case .unconfigured: Chip(text: "Setup")
        default: Chip(text: "Connect")
        }
    }
}
