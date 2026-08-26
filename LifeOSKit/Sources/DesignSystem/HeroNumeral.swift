import SwiftUI

/// The hero figure on a domain screen. A numeral is never shown without its unit.
public struct HeroNumeral: View {
    private let value: String
    private let unit: String?
    private let label: String

    public init(value: String, unit: String? = nil, label: String) {
        self.value = value
        self.unit = unit
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(value)
                    .font(LifeOSType.numeral(84, weight: .regular))
                    .tracking(-2)
                if let unit {
                    Text(unit).font(LifeOSType.screenTitle.weight(.regular)).opacity(0.85)
                }
            }
            Text(label)
                .font(LifeOSType.secondary.weight(.medium))
                .opacity(0.75)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

/// Shown in place of a `HeroNumeral` when the metric has no data.
/// A missing value must never look like a zero.
public struct HeroEmptyState: View {
    private let label: String
    private let reason: String

    public init(label: String, reason: String) {
        self.label = label
        self.reason = reason
    }

    public var body: some View {
        VStack(spacing: 6) {
            Text("—")
                .font(LifeOSType.numeral(84, weight: .semibold))
                .opacity(0.35)
            Text(label).font(LifeOSType.secondary.weight(.medium)).opacity(0.7)
            Text(reason).font(LifeOSType.label.weight(.regular)).opacity(0.5)
        }
    }
}
