import SwiftUI
import DesignSystem
import Integrations

struct ConnectionsScreen: View {
    @Bindable var model: OnboardingViewModel
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var fitbit: FitbitConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
    @Bindable var plaid: PlaidConnectionViewModel
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Text("Connect once.\nMake yourself at home.")
                    .font(.largeTitle.bold())
                Text("Choose a service, sign in, and approve what you share. LifeOS brings it together for you.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(spacing: Space.x2) {
                    connectionRow("WHOOP", detail: "Sleep, recovery and strain", status: whoop.statusDetail,
                        symbol: "bolt.heart", connected: whoop.isConnected,
                        busy: whoop.state == .connecting || whoop.isSyncing,
                        available: whoop.state != .unconfigured) { whoop.connect() }
                    connectionRow("Google Fitbit", detail: "Sleep, heart health and recovery", status: fitbit.statusDetail,
                        symbol: "figure.walk", connected: fitbit.isConnected,
                        busy: fitbit.state == .connecting || fitbit.isSyncing,
                        available: fitbit.state != .unconfigured) { fitbit.connect() }
                    connectionRow("Bank accounts", detail: "Balances and transactions, through Plaid", status: plaid.statusDetail,
                        symbol: "building.columns", connected: plaid.isConnected,
                        busy: plaid.state == .connecting || plaid.isSyncing,
                        available: plaid.state != .unconfigured) { plaid.connect() }
                    connectionRow("Apple Health", detail: "Health data from this iPhone", status: health.statusDetail,
                        symbol: "heart", connected: health.isConnected,
                        busy: health.state == .syncing,
                        available: health.state != .unavailable) { Task { await health.connect() } }
                }

                Label("Your connections belong to your LifeOS account.", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.medium))
                Text("Saved links stay available when you reopen the app. A provider may occasionally ask you to sign in again. Logging out closes access on this device; another account starts with its own data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Space.x3)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.x1) {
                OnboardingActionButton("Continue to LifeOS", action: onFinish)
                Text("All optional. Manage connections in Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(Space.x3)
            .background(LifeOSTokens.canvas.resolve(scheme))
        }
        .tint(LifeOSTokens.accent)
    }

    private func connectionRow(_ title: String, detail: String, status: String,
                               symbol: String, connected: Bool, busy: Bool,
                               available: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text(available ? status : "Available when this service is enabled")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if busy {
                    ProgressView().accessibilityLabel("Connecting \(title)")
                } else if connected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LifeOSTokens.accent)
                } else {
                    Button("Connect", action: action)
                        .font(.subheadline.bold())
                        .frame(minWidth: 68, minHeight: 44)
                        .disabled(!available)
                }
            }
        }
        .padding(Space.x2)
        .background(LifeOSTokens.cardSurface.resolve(scheme),
                    in: RoundedRectangle(cornerRadius: Radius.medium))
    }
}

/// Routes between the signup steps and the app itself.
struct OnboardingFlow: View {
    @Bindable var model: OnboardingViewModel
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var fitbit: FitbitConnectionViewModel
    @Bindable var plaid: PlaidConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
    let onFinish: () -> Void

    var body: some View {
        Group {
            switch model.step {
            case .intro:
                IntroScreen(
                    onStart: { model.beginSignup() },
                    onSignIn: { model.beginSignIn() }
                )
            case .identity:    IdentityScreen(model: model)
            case .code:        CodeScreen(model: model)
            case .profile:     ProfileStepScreen(model: model)
            case .connections: ConnectionsScreen(model: model, whoop: whoop, fitbit: fitbit, health: health, plaid: plaid, onFinish: onFinish)
            case .signedIn:    ProgressView().controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.step)
        .transition(.opacity)
        // Called from onChange rather than the `.signedIn` view body: a body can
        // run more than once for a single state, and onFinish flips persisted
        // app state.
        .onChange(of: model.step) { _, step in
            if step == .signedIn { onFinish() }
        }
    }
}
