import SwiftUI
import DesignSystem

struct BodyScreen: View {
    let snapshot: BodySnapshot

    var body: some View {
        GradientCanvas(hue: .body) {
            ScrollView {
                VStack(spacing: 28) {
                    if let weight = snapshot.weightKg {
                        HeroNumeral(value: String(format: "%.1f", weight), unit: "kg", label: "Bodyweight")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    } else {
                        HeroEmptyState(label: "Bodyweight", reason: "No weigh-in recorded")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    }

                    if let delta = snapshot.weeklyDeltaKg {
                        GlassCard {
                            HStack {
                                Text("This week").font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) kg")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LifeOSTokens.accent)
                            }
                        }
                        .foregroundStyle(.white)
                    }

                    SolidCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LAST 14 DAYS")
                                .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                            WeightBars(points: snapshot.recentWeights)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }
        }
    }
}

/// The vertical bar chart from the reference design.
private struct WeightBars: View {
    let points: [WeightPoint]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let weights = points.compactMap(\.weightKg)
        let low = weights.min() ?? 0
        let high = weights.max() ?? 1
        let span = max(high - low, 0.1)

        HStack(alignment: .bottom, spacing: 5) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(point.weightKg == nil
                          ? LifeOSTokens.dotMissed.resolve(scheme)
                          : LifeOSTokens.primaryText.resolve(scheme))
                    .frame(height: point.weightKg.map { 20 + ($0 - low) / span * 60 } ?? 6)
            }
        }
        .frame(height: 84)
    }
}

private func previewWeights() -> [WeightPoint] {
    var points: [WeightPoint] = []
    for index in 0..<14 {
        let day: Date = .now.addingTimeInterval(Double(index) * 86_400)
        let kg: Double? = index % 5 == 0 ? nil : 77 + Double(index % 4) * 0.3
        points.append(WeightPoint(id: day, weightKg: kg))
    }
    return points
}

#Preview {
    BodyScreen(snapshot: BodySnapshot(
        weightKg: 77.4,
        weeklyDeltaKg: -0.6,
        recentWeights: previewWeights()
    ))
}
