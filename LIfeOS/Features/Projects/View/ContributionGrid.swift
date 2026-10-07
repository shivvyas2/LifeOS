import SwiftUI
import DesignSystem
import Persistence

/// A year of daily counts as squares, a column per week, in a project
/// colour's ramp. `weeks` limits it to the most recent weeks.
struct ContributionGrid: View {
    let counts: [Int]
    var colour: ProjectColour = .moss
    var weeks: Int? = nil
    @Environment(\.colorScheme) private var scheme

    private var columns: [[Int]] {
        let levels = ContributionScale.levels(counts)
        var cols = stride(from: 0, to: levels.count, by: 7).map { Array(levels[$0..<min($0 + 7, levels.count)]) }
        if let weeks { cols = Array(cols.suffix(weeks)) }
        return cols
    }

    var body: some View {
        GeometryReader { proxy in
            let cols = columns
            let gap: CGFloat = 2
            let side = max(2, min(14, (proxy.size.width - gap * CGFloat(max(cols.count - 1, 0))) / CGFloat(max(cols.count, 1))))
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(cols.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, level in
                            Rectangle().fill(colour.ramp(level: level).resolve(scheme))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 7 * 9 + 6 * 2)
        .accessibilityElement()
        .accessibilityLabel("Contributions, \(counts.reduce(0, +)) this year")
    }
}
