import SwiftUI

/// A metric tile for a repeated row of stats: solid surface, dark text,
/// sentence-case label above the value.
///
/// Deliberately not a `SoftCard` wrapping a bare figure: `SoftCard`'s shadow is an
/// offscreen pass meant for screen furniture, not for a row of tiles that
/// repeats down a list.
public struct MetricTile: View {
    private let label: String
    private let value: String?
    private let unit: String?
    @Environment(\.colorScheme) private var scheme

    /// `value == nil` renders an em dash, never a zero.
    public init(label: String, value: String?, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .opacity(value == nil ? 0.4 : 1)
                if let unit, value != nil {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LifeOSTokens.tileSurface.resolve(scheme))
                .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 8, y: 2)
        )
    }
}

/// The pill switcher used to put several related sections behind one tab.
public struct SegmentedPill<Value: Hashable>: View {
    private let options: [(value: Value, title: String)]
    @Binding private var selection: Value
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Text(option.title)
                    .font(.system(size: 14, weight: .semibold))
                    // One line, always. Four titles at this size overflow a
                    // narrow phone, and an unconstrained Text answers that by
                    // wrapping, which makes one segment two lines tall and
                    // drags the whole pill with it. Shrinking the glyphs a
                    // little is the lesser cost.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(
                        isSelected
                            ? LifeOSTokens.primaryText.resolve(scheme)
                            : LifeOSTokens.secondaryText.resolve(scheme)
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    // Equal shares of whatever width there is, so the segments
                    // stay a row of matching pills instead of sizing to their
                    // own text and pushing the longest one off the edge.
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(LifeOSTokens.cardSurface.resolve(scheme))
                                .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 6, y: 2)
                        }
                    }
                    .contentShape(.capsule)
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(4)
        .background(Capsule().fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.06)))
    }
}

#Preview("Tiles") {
    GradientCanvas(hue: .activity) {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                MetricTile(label: "Distance", value: "6.7", unit: "km")
                MetricTile(label: "Active Time", value: "1h 12m")
                MetricTile(label: "Calories", value: nil, unit: "kcal")
            }
        }
        .padding()
    }
}
