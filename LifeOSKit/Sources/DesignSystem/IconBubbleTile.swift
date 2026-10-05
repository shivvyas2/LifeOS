import SwiftUI

/// The reference design's stat card: an icon in a pastel bubble, a quiet
/// label, and a big dark number. Sits directly on the canvas as a card.
public struct IconBubbleTile: View {
    private let icon: String
    private let hue: ModuleHue
    private let label: String
    private let value: String?
    private let unit: String?
    @Environment(\.colorScheme) private var scheme

    /// `value == nil` renders an em dash, never a zero.
    public init(icon: String, hue: ModuleHue, label: String, value: String?, unit: String? = nil) {
        self.icon = icon
        self.hue = hue
        self.label = label
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .lineLimit(2, reservesSpace: true)
                Spacer(minLength: 4)
                Image(systemName: icon)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(Editorial.rule(scheme)))
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(LifeOSType.numeral)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .opacity(value == nil ? 0.4 : 1)
                if let unit, value != nil {
                    Text(unit)
                        .font(LifeOSType.label)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Editorial.rule(scheme)))
    }
}

#Preview {
    HStack(spacing: 12) {
        IconBubbleTile(icon: "flame.fill", hue: .activity, label: "Calories Today", value: "1,450", unit: "kcal")
        IconBubbleTile(icon: "drop.fill", hue: .recovery, label: "Drink Water", value: nil, unit: "ml")
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
