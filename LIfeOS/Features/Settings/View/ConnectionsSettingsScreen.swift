import SwiftUI
import DesignSystem

/// Full-screen connections, not a cramped Settings section. All three
/// integrations are live: Whoop, Apple Health and bank accounts via Plaid.
///
/// Each source wears its own hue in the app's bubble vocabulary, the cards
/// are real glass, and the action sits in a chip: a verb when there is
/// something to do, a quiet green state when the connection is standing.
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
                    connectionCard(
                        icon: "bolt.heart.fill", hue: .recovery,
                        title: "Whoop", status: whoop.statusDetail,
                        chip: whoopChip
                    ) { showWhoop = true }

                    connectionCard(
                        icon: "heart.fill", hue: .body,
                        title: "Apple Health", status: health.statusDetail,
                        chip: healthChip
                    ) { Task { await health.connect() } }
                    .disabled(health.state == .unavailable)

                    connectionCard(
                        icon: "building.columns.fill", hue: .money,
                        title: "Bank accounts", status: plaid.statusDetail,
                        chip: bankChip
                    ) {
                        if case .connected = plaid.state {} else { plaid.connect() }
                    }
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

    // MARK: - The one card

    private func connectionCard(
        icon: String, hue: ModuleHue,
        title: String, status: String,
        chip: Chip, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(LifeOSType.body.weight(.semibold))
                    .foregroundStyle(hue.top)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(status)
                        .font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                chipView(chip)
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// A verb in a soft capsule, or the standing state with a check. The
    /// difference in colour is the difference in meaning: orange asks for a
    /// tap, green reports one that already happened.
    private struct Chip {
        let text: String
        var standing = false
    }

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        if chip.text.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                if chip.standing {
                    Image(systemName: "checkmark")
                        .font(LifeOSType.eyebrow.weight(.bold))
                }
                Text(chip.text)
                    .font(LifeOSType.label.weight(.semibold))
            }
            .foregroundStyle(chip.standing ? ModuleHue.money.top : LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(chip.standing
                               ? (scheme == .dark ? ModuleHue.money.pastelDark : ModuleHue.money.pastel)
                               : LifeOSTokens.accentSoft.resolve(scheme))
            )
        }
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
