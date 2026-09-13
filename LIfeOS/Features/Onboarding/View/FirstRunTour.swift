import SwiftUI
import DesignSystem

/// A single orientation after account setup. AppShell remembers completion
/// per account so this does not become another carousel on every sign-in.
struct FirstRunTour: View {
    var onDone: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .foregroundStyle(LifeOSTokens.accent)
                        Text("LifeOS").font(.title3.bold())
                        Spacer()
                        Button("Skip", action: onDone)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }

                    OnboardingCat(page: 0, isActive: scenePhase == .active)
                        .frame(height: min(180, max(125, geometry.size.height * 0.20)))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome home.")
                            .font(.largeTitle.bold())
                            .tracking(-0.8)
                            .accessibilityAddTraits(.isHeader)
                        Text("A few good places to start.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        guideRow("Start with Today", symbol: "sun.max",
                                 detail: "Your plans, habits and health at a glance.")
                        Divider().padding(.leading, 54)
                        guideRow("Connect your world", symbol: "link",
                                 detail: "WHOOP, Google Fitbit and banks through Plaid. Manage them in Settings.")
                        Divider().padding(.leading, 54)
                        guideRow("Talk it through", symbol: "bubble.left",
                                 detail: "Ask your coach for a quick answer or a clear next step.")
                    }
                    .background(LifeOSTokens.cardSurface.resolve(scheme),
                                in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingActionButton("Open my day", action: onDone)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .background(LifeOSTokens.canvas.resolve(scheme))
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .tint(LifeOSTokens.accent)
        }
    }

    private func guideRow(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(LifeOSTokens.accent)
                .frame(width: 26).frame(minHeight: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FirstRunTour(onDone: {})
}
