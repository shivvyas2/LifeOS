import SwiftUI
import DesignSystem
import Integrations

/// Final step. Every connection is optional and can be made later in Settings —
/// stated plainly, because a permission wall at signup is the fastest way to
/// lose someone before they have seen the app.
struct ConnectionsScreen: View {
    @Bindable var model: OnboardingViewModel
    @Bindable var whoop: WhoopConnectionViewModel
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SignupScaffold(
            title: "Connect your data",
            subtitle: "All optional. You can add or remove these any time in Settings.",
            onBack: { model.back() }
        ) {
            VStack(spacing: Space.x2) {
                connectionRow(
                    title: "Whoop",
                    detail: whoopDetail,
                    systemImage: "bolt.heart.fill",
                    isConnected: isWhoopConnected,
                    isAvailable: whoopAvailable
                ) {
                    whoop.connect()
                }

                connectionRow(
                    title: "Apple Health",
                    detail: "Steps, sleep and weight — arrives in the next release.",
                    systemImage: "heart.fill",
                    isConnected: false,
                    isAvailable: false
                ) {}

                connectionRow(
                    title: "Bank accounts",
                    detail: "Income and spending via Plaid — arrives in the next release.",
                    systemImage: "dollarsign.circle.fill",
                    isConnected: false,
                    isAvailable: false
                ) {}
            }
        } action: {
            VStack(spacing: Space.x1) {
                PrimaryButton(isWhoopConnected ? "Done" : "Continue") { onFinish() }
                if !isWhoopConnected {
                    Text("You can connect everything later.")
                        .font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
    }

    private var isWhoopConnected: Bool {
        if case .connected = whoop.state { return true }
        return false
    }

    private var whoopAvailable: Bool {
        if case .unconfigured = whoop.state { return false }
        return true
    }

    private var whoopDetail: String {
        switch whoop.state {
        case .unconfigured: "Not configured on this build."
        case .connected:    "Connected — recovery, sleep and strain."
        default:            "Recovery, sleep and strain."
        }
    }

    private func connectionRow(
        title: String, detail: String, systemImage: String,
        isConnected: Bool, isAvailable: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.x2) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .frame(width: Space.x5, height: Space.x5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(LifeOSTokens.canvas.resolve(scheme))
                )
                .foregroundStyle(isConnected ? LifeOSTokens.accent : LifeOSTokens.primaryText.resolve(scheme))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.x1)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LifeOSTokens.accent)
            } else {
                Button("Connect", action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .tint(LifeOSTokens.accent)
                    .disabled(!isAvailable)
                    .opacity(isAvailable ? 1 : 0.4)
            }
        }
        .padding(Space.x2)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
    }
}

/// Routes between the signup steps and the app itself.
struct OnboardingFlow: View {
    @Bindable var model: OnboardingViewModel
    @Bindable var whoop: WhoopConnectionViewModel
    let onFinish: () -> Void

    var body: some View {
        Group {
            switch model.step {
            case .intro:       IntroScreen { model.beginSignup() }
            case .identity:    IdentityScreen(model: model)
            case .code:        CodeScreen(model: model)
            case .linkSent:    LinkSentScreen(model: model)
            case .profile:     ProfileScreen(model: model)
            case .connections: ConnectionsScreen(model: model, whoop: whoop, onFinish: onFinish)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.step)
        .transition(.opacity)
    }
}
