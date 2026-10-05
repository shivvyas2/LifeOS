import SwiftUI
import DesignSystem

/// One reading on a paper card. The module hues that used to tint these
/// are gone: six pastels side by side were what made Health read as a
/// different app from the rest. `hue` stays so call sites need no change.
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
                Text(value ?? "—").font(Editorial.figure(34)).tracking(Editorial.figureTracking(34)).monospacedDigit()
                if let unit, value != nil { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.caption.weight(.medium))
                    .foregroundStyle(captionColor ?? LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .editorialCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}
