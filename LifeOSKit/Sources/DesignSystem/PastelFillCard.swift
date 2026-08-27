import SwiftUI

/// The reference's colored metric card: a pastel fill, a white icon bubble,
/// a quiet label, and a huge dark number. Sits next to its pair in a 2-up
/// grid. Distinct from `IconBubbleTile`, which is a white card with a pastel
/// chip — that look stays on Fitness.
public struct PastelFillCard: View {
    private let icon: String
    private let hue: ModuleHue
    private let label: String
    private let value: String?
    private let unit: String?
    private let caption: String?
    private let captionColor: Color?
    @Environment(\.colorScheme) private var scheme

    /// `value == nil` renders an em dash, never a zero.
    public init(
        icon: String,
        hue: ModuleHue,
        label: String,
        value: String?,
        unit: String? = nil,
        caption: String? = nil,
        captionColor: Color? = nil
    ) {
        self.icon = icon
        self.hue = hue
        self.label = label
        self.value = value
        self.unit = unit
        self.caption = caption
        self.captionColor = captionColor
    }

    public init(
        icon: String,
        hue: ModuleHue,
        label: String,
        split: SplitNumeral?,
        caption: String? = nil,
        captionColor: Color? = nil
    ) {
        self.init(
            icon: icon,
            hue: hue,
            label: label,
            value: split?.hero,
            unit: split?.remainder,
            caption: caption,
            captionColor: captionColor
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(LifeOSType.rowTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(width: 40, height: 40)
                .background(Circle().fill(LifeOSTokens.cardSurface.resolve(scheme)))

            Spacer(minLength: 16)

            Text(label)
                .font(LifeOSType.label)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme).opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.bottom, 4)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value ?? "—")
                    .font(LifeOSType.numeralLarge)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .opacity(value == nil ? 0.4 : 1)
                if let unit, value != nil {
                    Text(unit)
                        .font(LifeOSType.body.weight(.medium))
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme).opacity(0.45))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            if let caption {
                Text(caption)
                    .font(LifeOSType.eyebrow.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(captionColor ?? LifeOSTokens.secondaryText.resolve(scheme))
                    .padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(scheme == .dark ? hue.pastelDark : hue.pastel)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [label]
        if let value {
            parts.append(unit.map { "\(value) \($0)" } ?? value)
        }
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    HStack(spacing: 12) {
        PastelFillCard(
            icon: "heart.fill",
            hue: .nutrition,
            label: "Recovery",
            value: "86",
            unit: "%",
            caption: "High",
            captionColor: RecoveryBand.high.color
        )
        PastelFillCard(
            icon: "moon.fill",
            hue: .money,
            label: "Sleep",
            split: .sleep(minutes: 432)
        )
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
