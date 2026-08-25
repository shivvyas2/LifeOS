import SwiftUI

/// The reference design's weekly chart: a full-height soft track per day with
/// a solid rounded bar inside it, scaled to the week's maximum.
public struct RoundedBarChart: View {
    public struct Bar: Identifiable, Equatable, Sendable {
        public let id: Date
        public let label: String
        public let value: Double?

        public init(id: Date, label: String, value: Double?) {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    private let bars: [Bar]
    @Environment(\.colorScheme) private var scheme

    public init(bars: [Bar]) {
        self.bars = bars
    }

    public var body: some View {
        let peak = max(bars.compactMap(\.value).max() ?? 1, 1)

        HStack(alignment: .bottom, spacing: 10) {
            ForEach(bars) { bar in
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            // The track: always full height, so a light week
                            // still reads as seven days, not four.
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LifeOSTokens.accentSoft.resolve(scheme))
                            if let value = bar.value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LifeOSTokens.accent)
                                    .frame(height: max(geo.size.height * value / peak, 10))
                            } else {
                                // A day with no reading is a gap, not a zero.
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(LifeOSTokens.dotMissed.resolve(scheme))
                                    .frame(height: 6)
                            }
                        }
                    }

                    Text(bar.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
        .frame(height: 150)
    }
}

#Preview {
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    RoundedBarChart(bars: days.enumerated().map { index, label in
        RoundedBarChart.Bar(id: Date().addingTimeInterval(Double(index) * 86_400),
                            label: label,
                            value: index == 4 ? nil : Double(200 + index * 130))
    })
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
