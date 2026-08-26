import SwiftUI
import UIKit
import DesignSystem

/// Glass overlay for connecting or syncing Whoop. Replaces the cramped
/// Settings row so the OAuth round-trip has a surface of its own.
struct WhoopConnectModal: View {
    @State private var hasWaited = false
    @Bindable var model: WhoopConnectionViewModel
    var onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.62 : 0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    if case .connecting = model.state { return }
                    onDismiss()
                }

            VStack(spacing: 16) {
                GlassPanel(radius: Radius.large) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "bolt.heart.fill")
                                .font(LifeOSType.body.weight(.semibold))
                                .foregroundStyle(LifeOSTokens.accent)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Whoop")
                                    .font(LifeOSType.sectionTitle.weight(.bold))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                Text(model.statusDetail)
                                    .font(LifeOSType.label)
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            }
                            Spacer()
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(LifeOSType.label.weight(.bold))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                    .frame(width: 36, height: 36)
                                    .contentShape(Circle())
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                        }

                        Text("Recovery, sleep, strain and workouts land here once Whoop is connected. Sync pulls the last fortnight.")
                            .font(LifeOSType.label.weight(.regular))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        actions
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    /// What a bare `ProgressView` used to be.
    ///
    /// Connecting hands off to Safari, and Whoop's login sits behind a
    /// Cloudflare check that stalls indefinitely behind a VPN, Private Relay
    /// or a content blocker: no error, no callback, nothing to tap. A spinner
    /// alone tells someone in that state to keep waiting for something that is
    /// never going to happen. So it says where the sign-in actually is, and
    /// after a few seconds offers the two ways out.
    private var waitingForSafari: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finish signing in with Whoop in Safari.")
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                Spacer(minLength: 0)
            }

            if hasWaited {
                Text("Still here? Whoop's page sometimes stalls behind a VPN, Private Relay or a content blocker.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Sign in on a computer instead") { model.beginManual() }
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(maxWidth: .infinity)

                Button("Cancel") { model.cancelConnect() }
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .task(id: model.statusDetail) {
            // Long enough that a sign-in going normally never shows it, short
            // enough that someone staring at a stalled page is not left there.
            hasWaited = false
            try? await Task.sleep(for: .seconds(6))
            hasWaited = true
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.state {
        case .unconfigured:
            Text("Add the Whoop client ID and deploy whoop-token to enable.")
                .font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        case .disconnected, .failed:
            PrimaryButton("Connect Whoop") { model.connect() }
            Button("Sign in on another device") { model.beginManual() }
                .font(LifeOSType.label)
                .foregroundStyle(LifeOSTokens.accent)
                .frame(maxWidth: .infinity)
        case .connecting:
            if let url = model.manualURL {
                manualSteps(url: url)
            } else {
                waitingForSafari
            }
        case .connected:
            PrimaryButton("Sync now") { Task { await model.sync() } }
            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
            .font(LifeOSType.label)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func manualSteps(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Open this link on a computer and sign in to Whoop.")
                .font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Button {
                UIPasteboard.general.string = url.absoluteString
            } label: {
                Label("Copy sign-in link", systemImage: "doc.on.doc")
                    .font(LifeOSType.label.weight(.semibold))
            }
            .tint(LifeOSTokens.accent)

            Text("2. Paste the code it shows you:")
                .font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            TextField("Code", text: $model.manualCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(LifeOSType.mono())

            HStack(spacing: 16) {
                Button("Connect") { Task { await model.submitManualCode() } }
                    .font(LifeOSType.rowTitle)
                    .disabled(model.manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(LifeOSTokens.accent)
                Button("Cancel", role: .cancel) { model.cancelManual() }
                    .font(LifeOSType.label.weight(.regular))
            }
        }
    }
}
