import SwiftUI
import DesignSystem

/// Module colors identify readings without implying a healthy or unhealthy result.
struct HealthReadingCard: View {
    let icon: String
    let label: String
    let value: String?
    var unit: String? = nil
    var caption: String? = nil
    var captionColor: Color? = nil
    var hue: ModuleHue = .body
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(label, systemImage: icon).font(LifeOSType.label)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme).opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "—").font(.title.bold()).monospacedDigit()
                if let unit, value != nil { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.caption.weight(.medium))
                    .foregroundStyle(captionColor ?? LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(16)
        .background(scheme == .dark ? hue.pastelDark : hue.pastel, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}
