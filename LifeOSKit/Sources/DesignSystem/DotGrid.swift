import SwiftUI

public struct DotGrid: View {
    private let cells: [DotCell]
    private let dotSize: CGFloat
    /// Built once in `init` rather than per `body`. The grid redraws on scroll,
    /// and rebuilding the column array each pass is pure allocation churn.
    private let columns: [GridItem]
    @Environment(\.colorScheme) private var scheme

    public init(cells: [DotCell], dotSize: CGFloat = 22) {
        self.cells = cells
        self.dotSize = dotSize
        self.columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cells) { cell in
                Circle()
                    .fill(fill(for: cell.state))
                    .overlay {
                        if cell.state == .noData {
                            Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
                        }
                    }
                    .frame(width: dotSize, height: dotSize)
                    .opacity(cell.state == .blank ? 0 : 1)
            }
        }
    }

    private func fill(for state: DotState) -> Color {
        switch state {
        case .onTarget: LifeOSTokens.primaryText.resolve(scheme)
        case .missed:   LifeOSTokens.dotMissed.resolve(scheme)
        case .today:    LifeOSTokens.accent
        case .future:   LifeOSTokens.dotFuture.resolve(scheme)
        case .noData:   .clear
        case .blank:    .clear
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
