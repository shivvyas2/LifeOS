import SwiftUI
import DesignSystem

struct RecoverySection: View {
    let snapshot: RecoverySnapshot

    var body: some View {
        VStack(spacing: 24) {
            if let recovery = snapshot.recoveryPct {
                HeroNumeral(value: "\(Int(recovery))", unit: "%", label: "Recovery")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Recovery", reason: "Connect Whoop in Settings")
                    .foregroundStyle(LifeOSTokens.onGradient)
                    .padding(.top, 18)
            }

            HStack(spacing: 10) {
                MetricTile(label: "HRV", value: snapshot.hrvMs.map { "\(Int($0))" }, unit: "ms")
                MetricTile(label: "Strain", value: snapshot.dayStrain.map { String(format: "%.1f", $0) })
                MetricTile(label: "Sleep", value: snapshot.sleepMinutes.map { "\($0 / 60)h \($0 % 60)m" })
            }
        }
    }
}

#Preview("Empty — the real first run") {
    ZStack {
        LinearGradient(colors: [ModuleHue.recovery.top, ModuleHue.recovery.bottom],
                       startPoint: .top, endPoint: .bottom)
        RecoverySection(snapshot: RecoverySnapshot(hrvMs: 62, sleepMinutes: 432))
            .padding()
    }
    .ignoresSafeArea()
}
