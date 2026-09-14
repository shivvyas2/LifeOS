import SwiftUI
import DesignSystem

/// Bodyweight for the selected day, plus its recent trend.
struct WeightSection: View {
    let snapshot: BodySnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("Weight", systemImage: "scalemass").font(.headline)
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.weightKg.map { String(format: "%.1f kg", $0) } ?? "No weigh-in")
                        .font(.title.bold()).monospacedDigit()
                    Spacer()
                    if let delta = snapshot.weeklyDeltaKg {
                        Text(String(format: "%+.1f kg this week", delta))
                            .font(.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                }
                WeightBars(points: snapshot.recentWeights)
                Text("\(snapshot.recentWeights.count { $0.weightKg != nil }) of 14 days recorded · Scale follows your weight range")
                    .font(.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
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
