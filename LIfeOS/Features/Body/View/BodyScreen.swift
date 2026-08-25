import SwiftUI
import DesignSystem

/// Bodyweight for the selected day, plus its recent trend.
struct WeightSection: View {
    let snapshot: BodySnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 24) {
            if let weight = snapshot.weightKg {
                HeroNumeral(value: String(format: "%.1f", weight), unit: "kg", label: "Bodyweight")
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.top, 18)
            } else {
                HeroEmptyState(label: "Bodyweight", reason: "No weigh-in recorded")
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.top, 18)
            }

            HStack(spacing: 10) {
                MetricTile(
                    label: "This week",
                    value: snapshot.weeklyDeltaKg.map { "\($0 >= 0 ? "+" : "")\(String(format: "%.1f", $0))" },
                    unit: "kg"
                )
                MetricTile(
                    label: "Logged",
                    value: "\(snapshot.recentWeights.count { $0.weightKg != nil })",
                    unit: "of 14"
                )
            }

            SoftCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LAST 14 DAYS")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    WeightBars(points: snapshot.recentWeights)
                }
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
    GradientCanvas(hue: .body) {
        ScrollView {
            WeightSection(snapshot: BodySnapshot(
                weightKg: 77.4, weeklyDeltaKg: -0.6, recentWeights: previewWeights()
            ))
            .padding()
        }
    }
}
