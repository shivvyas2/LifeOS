import SwiftUI
import DesignSystem

/// Full-screen connections, not a cramped Settings section. Whoop is live;
/// the others are named so the empty slots are honest rather than hidden.
struct ConnectionsSettingsScreen: View {
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var showWhoop = false

    var body: some View {
        GradientCanvas(hue: .recovery) {
            ScrollView {
                VStack(spacing: 14) {
                    whoopCard

                    healthCard
                    comingSoon(
                        title: "Bank accounts",
                        detail: "Income and spending via Plaid. Arrives in the next release.",
                        systemImage: "dollarsign.circle.fill"
                    )
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Whoop")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(whoop.statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }

                Spacer()

                Text(whoopActionTitle)
                    .font(.system(size: 13, weight: .semibold))
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Health")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(health.statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(healthActionTitle)
                    .font(.system(size: 13, weight: .semibold))
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

    private var whoopActionTitle: String {
        switch whoop.state {
        case .connected: "Sync"
        case .connecting: "…"
        case .unconfigured: "Setup"
        default: "Connect"
        }
    }

    private func comingSoon(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 44, height: 44)
                .background(Circle().fill(LifeOSTokens.tileSurface.resolve(scheme)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
                .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 12, y: 4)
        )
        .opacity(0.7)
    }
}
