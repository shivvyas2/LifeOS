import SwiftUI
import DesignSystem

/// Full-screen connections, not a cramped Settings section. All three
/// integrations are live: Whoop, Apple Health and bank accounts via Plaid.
struct ConnectionsSettingsScreen: View {
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
    @Bindable var plaid: PlaidConnectionViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showWhoop = false

    var body: some View {
        GradientCanvas(hue: .recovery) {
            ScrollView {
                VStack(spacing: 14) {
                    whoopCard

                    healthCard
                    bankCard
                }
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

    private var whoopCard: some View {
        Button { showWhoop = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.heart.fill")
                    .font(LifeOSType.body.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Whoop")
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(whoop.statusDetail)
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                Spacer()

                Text(whoopActionTitle)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }

    /// Health has no modal of its own: there is nothing to configure and no
    /// account to enter. The row either opens the system prompt or re-reads.
    private var healthCard: some View {
        Button {
            Task { await health.connect() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(LifeOSType.body.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Health")
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(health.statusDetail)
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(healthActionTitle)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
        .disabled(health.state == .unavailable)
    }

    private var healthActionTitle: String {
        switch health.state {
        case .unavailable: ""
        case .notAsked:    "Connect"
        case .syncing:     "…"
        // "Sync" rather than "Connect" once asked: iOS shows the permission
        // sheet exactly once, so offering to connect again would be a button
        // that visibly does nothing.
        case .synced, .noData, .failed: "Sync"
        }
    }

    private var bankCard: some View {
        Button {
            if case .connected = plaid.state {} else { plaid.connect() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(LifeOSType.body.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bank accounts")
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(plaid.statusDetail)
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                Spacer()

                Text(bankActionTitle)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }

    private var bankActionTitle: String {
        switch plaid.state {
        // The tap only connects, so the connected row shows a state, not a verb.
        case .connected: "Connected"
        case .connecting: "…"
        case .unconfigured: "Setup"
        default: "Connect"
        }
    }

    private var whoopActionTitle: String {
        switch whoop.state {
        case .connected: "Sync"
        case .connecting: "…"
        case .unconfigured: "Setup"
        default: "Connect"
        }
    }

}
