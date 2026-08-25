import SwiftUI
import UIKit
import DesignSystem

/// Glass overlay for connecting or syncing Whoop. Replaces the cramped
/// Settings row so the OAuth round-trip has a surface of its own.
struct WhoopConnectModal: View {
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
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LifeOSTokens.accent)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(LifeOSTokens.accentSoft.resolve(scheme)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Whoop")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                Text(model.statusDetail)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            }
                            Spacer()
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                    .frame(width: 36, height: 36)
                                    .contentShape(Circle())
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                        }

                        Text("Recovery, sleep, strain and workouts land here once Whoop is connected. Sync pulls the last fortnight.")
                            .font(.system(size: 14))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        actions
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.state {
        case .unconfigured:
            Text("Add the Whoop client ID and deploy whoop-token to enable.")
                .font(.system(size: 13))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        case .disconnected, .failed:
            PrimaryButton("Connect Whoop") { model.connect() }
            Button("Sign in on another device") { model.beginManual() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LifeOSTokens.accent)
                .frame(maxWidth: .infinity)
        case .connecting:
            if let url = model.manualURL {
                manualSteps(url: url)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        case .connected:
            PrimaryButton("Sync now") { Task { await model.sync() } }
            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func manualSteps(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Open this link on a computer and sign in to Whoop.")
                .font(.system(size: 13))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            Button {
                UIPasteboard.general.string = url.absoluteString
            } label: {
                Label("Copy sign-in link", systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
            }
            .tint(LifeOSTokens.accent)

            Text("2. Paste the code it shows you:")
                .font(.system(size: 13))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            TextField("Code", text: $model.manualCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14, design: .monospaced))

            HStack(spacing: 16) {
                Button("Connect") { Task { await model.submitManualCode() } }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(model.manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(LifeOSTokens.accent)
                Button("Cancel", role: .cancel) { model.cancelManual() }
                    .font(.system(size: 14))
            }
        }
    }
}
