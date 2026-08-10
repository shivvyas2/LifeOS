import SwiftUI

public struct StatTile: View {
    private let label: String
    private let value: String?
    private let unit: String?
    private let progress: Double?
    @Environment(\.colorScheme) private var scheme

    /// `value == nil` renders an em dash, never a zero.
    public init(label: String, value: String?, unit: String? = nil, progress: Double? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .opacity(0.55)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(.system(size: 26, weight: .semibold))
                    .opacity(value == nil ? 0.35 : 1)
                if let unit, value != nil {
                    Text(unit).font(.system(size: 13, weight: .medium)).opacity(0.6)
                }
            }

            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(progress >= 1 ? LifeOSTokens.accent : LifeOSTokens.primaryText.resolve(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
