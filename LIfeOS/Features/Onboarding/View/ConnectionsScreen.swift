import SwiftUI
import DesignSystem
import Integrations

/// Final step. Every connection is optional and can be made later in Settings.
/// That is stated plainly, because a permission wall at signup is the fastest way to
/// lose someone before they have seen the app.
struct ConnectionsScreen: View {
    @Bindable var model: OnboardingViewModel
    @Bindable var whoop: WhoopConnectionViewModel
    @Bindable var health: HealthConnectionViewModel
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
                    detail: health.statusDetail,
                    systemImage: "heart.fill",
                    isConnected: health.isConnected,
                    isAvailable: health.state != .unavailable
                ) {
                    Task { await health.connect() }
                }

                connectionRow(
                    title: "Bank accounts",
                    detail: "Income and spending, straight from your bank.",
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
                        .font(LifeOSType.label.weight(.regular))
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
        case .connected:    "Connected. Recovery, sleep and strain."
        default:            "Recovery, sleep and strain."
        }
    }

    private func connectionRow(
        title: String, detail: String, systemImage: String,
        isConnected: Bool, isAvailable: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.x2) {
            Image(systemName: systemImage)
                .font(LifeOSType.body)
                .frame(width: Space.x5, height: Space.x5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(LifeOSTokens.canvas.resolve(scheme))
                )
                .foregroundStyle(isConnected ? LifeOSTokens.accent : LifeOSTokens.primaryText.resolve(scheme))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LifeOSType.rowTitle)
                Text(detail)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.x1)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(LifeOSType.sectionTitle.weight(.regular))
                    .foregroundStyle(LifeOSTokens.accent)
            } else {
                Button("Connect", action: action)
                    .font(LifeOSType.label.weight(.semibold))
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
    @Bindable var health: HealthConnectionViewModel
    let onFinish: () -> Void
    /// TEMPORARY: enters the app without an account so the rest of it can be
    /// tested while email delivery is still being sorted out. Signup is meant
    /// to be required, so remove this and the buttons that call it before
    /// shipping, or the requirement is theatre.
    var onSkipAuth: (() -> Void)?

    var body: some View {
        Group {
            switch model.step {
            case .intro:
                IntroScreen(
                    onStart: { model.beginSignup() },
                    onSignIn: { model.beginSignIn() },
                    onSkipAuth: onSkipAuth
                )
            case .identity:    IdentityScreen(model: model, onSkipAuth: onSkipAuth)
            case .code:        CodeScreen(model: model)
            case .profile:     ProfileScreen(model: model)
            case .connections: ConnectionsScreen(model: model, whoop: whoop, health: health, onFinish: onFinish)
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
