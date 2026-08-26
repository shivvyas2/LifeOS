import SwiftUI
import DesignSystem

/// A titled panel of label and value rows, with an optional baseline delta.
struct StatGroup: View {
    struct Row: Identifiable {
        let label: String
        let value: String?
        var delta: String?
        var id: String { label }
    }

    let title: String
    let rows: [Row]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // A group with nothing in it is not an empty panel, it is absent.
        if rows.contains(where: { $0.value != nil }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(LifeOSType.eyebrow.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .padding(.bottom, 8)

                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(LifeOSType.label)
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        Spacer(minLength: 8)
                        if let delta = row.delta, row.value != nil {
                            Text(delta)
                                .font(LifeOSType.caption.weight(.semibold))
                                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        }
                        Text(row.value ?? "—")
                            .font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                            .opacity(row.value == nil ? 0.4 : 1)
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.tileSurface.resolve(scheme))
            )
        }
    }
}
