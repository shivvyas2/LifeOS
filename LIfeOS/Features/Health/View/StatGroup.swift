import SwiftUI
import DesignSystem

/// A category with a featured reading and a scannable grid of supporting values.
struct StatGroup: View {
    struct Row: Identifiable {
        let label: String
        let value: String?
        var delta: String?
        var id: String { label }
    }

    let title: String
    let rows: [Row]
    var hue: ModuleHue = .body
    var icon: String = "chart.bar.xaxis"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let featured = rows.first(where: { $0.value != nil }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.headline)
                        .frame(width: 38, height: 38)
                        .background(LifeOSTokens.cardSurface.resolve(scheme).opacity(0.65), in: Circle())
                    Text(title).font(LifeOSType.sectionTitle)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(featured.label).font(LifeOSType.label)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme).opacity(0.65))
                    Text(featured.value ?? "—").font(.largeTitle.weight(.semibold)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let delta = featured.delta {
                        Text("\(delta) from your baseline").font(LifeOSType.caption)
                    }
                }.accessibilityElement(children: .combine)
                let remaining = rows.filter { $0.id != featured.id && $0.value != nil }
                if !remaining.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 135), alignment: .leading)], spacing: 16) {
                        ForEach(remaining) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.label).font(LifeOSType.caption)
                                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme).opacity(0.65))
                                Text(row.value ?? "—").font(LifeOSType.rowTitle).monospacedDigit()
                                if let delta = row.delta { Text(delta).font(LifeOSType.caption) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 14)
                            .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? hue.pastelDark : hue.pastel, in: RoundedRectangle(cornerRadius: 26))
        }
    }
}
