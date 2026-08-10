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
    @Environment(\.colorScheme) private var scheme

    public init(cells: [DotCell], dotSize: CGFloat? = 22, spacing: CGFloat = 8) {
        self.cells = cells
        self.dotSize = dotSize
        self.columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cells) { cell in
                dot(for: cell)
            }
        }
    }

    @ViewBuilder
    private func dot(for cell: DotCell) -> some View {
        let shape = Circle()
            .fill(fill(for: cell.state))
            .overlay {
                if cell.state == .noData {
                    Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
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
        case .missed:   LifeOSTokens.dotMissed.resolve(scheme)
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
