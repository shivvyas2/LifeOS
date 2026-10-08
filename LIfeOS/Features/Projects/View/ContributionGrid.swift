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

    /// Weeks as columns, each row a fixed weekday. `counts` ends today, so
    /// the front is padded with blanks (nil) until the last count lands on
    /// today's row: cut in plain sevens from the oldest day instead, every
    /// row's weekday drifted with however many days the year happened to
    /// start mid-week, and the newest column was not this week.
    private var columns: [[Int?]] {
        let levels = ContributionScale.levels(counts)
        let calendar = Calendar.current
        let todayRow = (calendar.component(.weekday, from: .now) - calendar.firstWeekday + 7) % 7
        let lead = ((todayRow + 1 - levels.count) % 7 + 7) % 7
        let cells: [Int?] = Array(repeating: nil, count: lead) + levels.map { Optional($0) }
        var cols = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
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
                            Rectangle().fill(level.map { colour.ramp(level: $0).resolve(scheme) } ?? .clear)
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
