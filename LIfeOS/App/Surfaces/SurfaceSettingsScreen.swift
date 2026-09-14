import SwiftUI
import DesignSystem

struct SurfaceSettingsScreen: View {
    @State private var surfaces = SurfaceCoordinator.shared
    @State private var sharing = SurfaceCoordinator.shared.sharingEnabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AccountPageHeading(title: "Your day, closer.", detail: "A glance on your screen. A little progress on your wrist.")
                    AccountPanel {
                        Toggle(isOn: $sharing) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Share health with widgets & Watch").font(LifeOSType.rowTitle)
                                Text("Steps, sleep and movement from this account. Turn off to clear the shared snapshot.")
                                    .font(LifeOSType.secondary).foregroundStyle(.secondary)
                            }
                        }.tint(LifeOSTokens.accent)
                    }
                    guide("Home Screen", icon: "square.grid.2x2", detail: "Touch and hold your Home Screen, choose Edit → Add Widget, then search for Almanac. Available on iPhone and iPad.")
                    guide("Lock Screen", icon: "lock", detail: "Touch and hold your Lock Screen, choose Customize, then Add Widgets. Pick Your day or Begin activity.")
                    guide("Apple Watch", icon: "applewatch", detail: "Install Almanac from the Watch app on your iPhone. Add Your day to the Smart Stack or a compatible watch face.")
                    guide("Activity timer", icon: "timer", detail: "Begin an activity in Almanac to show its timer on the Lock Screen and supported Dynamic Island. Tap it to pause, resume or finish in the app.")
                    Button("Open system settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(LifeOSType.rowTitle).padding(.vertical, 8)
                    Text("Widgets update after Almanac syncs; Apple controls refresh timing. Watch data expires after six hours or at midnight. Signing out clears this device immediately and sends a clear request to your Watch when it reconnects.")
                        .font(LifeOSType.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: 680).frame(maxWidth: .infinity).padding(20)
            }
        }.navigationTitle("Widgets & Watch").navigationBarTitleDisplayMode(.inline)
            .tint(LifeOSTokens.accent)
            .onChange(of: sharing) { _, value in surfaces.sharingEnabled = value }
    }
    private func guide(_ title: String, icon: String, detail: String) -> some View {
        AccountPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(LifeOSTokens.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(LifeOSType.sectionTitle)
                    Text(detail).font(LifeOSType.secondary).foregroundStyle(.secondary)
                }
            }
        }
    }
}
