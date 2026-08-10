import SwiftUI

/// A metric tile for use on a saturated gradient: light translucent surface,
/// dark text, sentence-case label above the value.
///
/// Deliberately not `GlassCard { StatTile { } }`. Material plus white text over
/// a mid-saturation hue is the low-contrast failure the reference designs avoid
/// — they keep the surface light and the text dark.
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
                    .foregroundStyle(
                        isSelected
                            ? LifeOSTokens.primaryText.resolve(scheme)
                            : LifeOSTokens.onGradient.opacity(0.75)
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background {
                        if isSelected {
                            Capsule().fill(LifeOSTokens.tileSurface.resolve(scheme))
                        }
                    }
                    .contentShape(.capsule)
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(4)
        .background(Capsule().fill(LifeOSTokens.onGradient.opacity(0.14)))
    }
}

#Preview("Tiles") {
    ZStack {
        LinearGradient(colors: [ModuleHue.activity.top, ModuleHue.activity.bottom],
                       startPoint: .top, endPoint: .bottom)
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                MetricTile(label: "Distance", value: "6.7", unit: "km")
                MetricTile(label: "Active Time", value: "1h 12m")
                MetricTile(label: "Calories", value: nil, unit: "kcal")
            }
        }
        .padding()
    }
    .ignoresSafeArea()
}
