import SwiftUI

public struct DotGrid: View {
    private let cells: [DotCell]
    /// `nil` lets each dot expand to fill its column, which is how the month
    /// view reads as a dense block. A fixed size is for inline uses that must
    /// not grow, like a streak strip inside a card.
    private let dotSize: CGFloat?
    /// Built once in `init` rather than per `body`. The grid redraws on scroll,
    /// and rebuilding the column array each pass is pure allocation churn.
    private let columns: [GridItem]
    /// Nil leaves the grid a pure readout, which is what the habit strips on the
    /// Plan tab want. The month grid passes a closure and becomes navigable.
    private let onTap: ((DotCell) -> Void)?
    @Environment(\.colorScheme) private var scheme

    public init(
        cells: [DotCell],
        dotSize: CGFloat? = 22,
        spacing: CGFloat = 8,
        onTap: ((DotCell) -> Void)? = nil
    ) {
        self.cells = cells
        self.dotSize = dotSize
        self.columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
        self.onTap = onTap
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cells) { cell in
                if let onTap, isTappable(cell) {
                    // The label is a `Circle`, whose hit region is the filled
                    // path — corners of the cell fall through without this,
                    // and `.missed`/`.noData` dots are filled `.clear`, which
                    // is hit-testable but leaves no visual confirmation the
                    // whole cell is tappable.
                    Button { onTap(cell) } label: { dot(for: cell).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(for: cell))
                } else {
                    dot(for: cell)
                        .accessibilityLabel(label(for: cell))
                        // Padding cells are layout, not days. Announcing them
                        // would put six silent stops in front of every month.
                        .accessibilityHidden(cell.date == nil)
                }
            }
        }
    }

    /// Padding cells are not days, and a day that has not happened yet has
    /// nothing to open. Both stay inert rather than presenting an empty sheet.
    private func isTappable(_ cell: DotCell) -> Bool {
        cell.date != nil && cell.state != .future && cell.state != .blank
    }

    private func label(for cell: DotCell) -> String {
        guard let date = cell.date else { return "" }
        return "\(date.formatted(.dateTime.day().month(.wide))), \(description(of: cell.state))"
    }

    private func description(of state: DotState) -> String {
        switch state {
        case .onTarget: "on target"
        case .missed:   "off target"
        case .today:    "today"
        case .future:   "upcoming"
        case .noData:   "no data"
        case .blank:    ""
        }
    }

    @ViewBuilder
    private func dot(for cell: DotCell) -> some View {
        let shape = Circle()
            .fill(fill(for: cell.state))
            .overlay {
                switch cell.state {
                case .missed:
                    // Hollow, per the spec: a missed day must read differently
                    // from a day that has not happened yet. Two greys of
                    // slightly different value did not carry that.
                    Circle().strokeBorder(
                        LifeOSTokens.primaryText.resolve(scheme).opacity(0.38),
                        lineWidth: max(1, dotSize.map { $0 / 14 } ?? 1.6)
                    )
                case .noData:
                    Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
                default:
                    EmptyView()
                }
            }

        if let dotSize {
            shape.frame(width: dotSize, height: dotSize)
        } else {
            shape.aspectRatio(1, contentMode: .fit)
        }
    }

    private func fill(for state: DotState) -> Color {
        switch state {
        case .onTarget: LifeOSTokens.primaryText.resolve(scheme)
        case .missed:   .clear
        case .today:    LifeOSTokens.accent
        case .future:   LifeOSTokens.dotFuture.resolve(scheme)
        case .noData:   .clear
        case .blank:    LifeOSTokens.dotPadding.resolve(scheme)
        }
    }
}

private let dotGridPreviewCells: [DotCell] = (0..<42).map { index in
    DotCell(id: index, date: nil, state: [.onTarget, .missed, .today, .future, .noData][index % 5])
}

/// Dated cells, because the interactive preview needs `date != nil` to show any
/// tap affordance at all.
private let dotGridDatedPreviewCells: [DotCell] = (0..<42).map { index in
    DotCell(
        id: index,
        date: Calendar.current.date(byAdding: .day, value: index, to: .now),
        state: [.onTarget, .missed, .today, .future, .noData][index % 5]
    )
}

#Preview("Light") {
    DotGrid(cells: dotGridPreviewCells)
        .padding()
        .background(LifeOSTokens.canvas.light)
}

#Preview("Dark") {
    DotGrid(cells: dotGridPreviewCells)
        .padding()
        .background(LifeOSTokens.canvas.dark)
        .preferredColorScheme(.dark)
}

#Preview("Interactive") {
    DotGrid(cells: dotGridDatedPreviewCells, dotSize: nil) { cell in
        print("tapped \(String(describing: cell.date))")
    }
    .padding()
    .background(LifeOSTokens.canvas.light)
}
