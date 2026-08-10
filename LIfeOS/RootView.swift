import SwiftUI
import DesignSystem
import Persistence

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var showQuickLog = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                Tab("Today", systemImage: "circle.grid.3x3.fill") { TodayScreen() }
                Tab("Body", systemImage: "figure") { BodyScreen() }
                Tab("Activity", systemImage: "flame.fill") { ActivityScreen() }
                Tab("Recovery", systemImage: "bolt.heart.fill") { RecoveryScreen() }
                Tab("Settings", systemImage: "gearshape.fill") { SettingsScreen() }
            }

            Button {
                showQuickLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(LifeOSTokens.primaryText.resolve(scheme)))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 72)
            .accessibilityLabel("Quick log")
        }
        .sheet(isPresented: $showQuickLog) { QuickLogSheet() }
    }
}
