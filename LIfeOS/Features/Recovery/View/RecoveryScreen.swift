import SwiftUI
import DesignSystem

struct RecoveryScreen: View {
    let snapshot: RecoverySnapshot

    var body: some View {
        GradientCanvas(hue: .recovery) {
            ScrollView {
                VStack(spacing: 28) {
                    if let recovery = snapshot.recoveryPct {
                        HeroNumeral(value: "\(Int(recovery))", unit: "%", label: "Recovery")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    } else {
                        HeroEmptyState(label: "Recovery", reason: "Connect Whoop in Settings")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    }

                    HStack(spacing: 10) {
                        GlassCard {
                            StatTile(label: "HRV", value: snapshot.hrvMs.map { "\(Int($0))" }, unit: "ms")
                        }
                        GlassCard {
                            StatTile(label: "Strain", value: snapshot.dayStrain.map { String(format: "%.1f", $0) })
                        }
                        GlassCard {
                            StatTile(label: "Sleep", value: snapshot.sleepMinutes.map { "\($0 / 60)h \($0 % 60)m" })
                        }
                    }
                    .foregroundStyle(.white)
                }
                .padding(20)
                .padding(.bottom, 120)
            }
        }
    }
}

#Preview("Empty — the real first run") {
    RecoveryScreen(snapshot: RecoverySnapshot(hrvMs: 62, sleepMinutes: 432))
}
