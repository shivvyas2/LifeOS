import SwiftUI

/// The onboarding animation: a month of dots filling in, one by one.
///
/// Deliberately the app's own vocabulary rather than decorative motion. The
/// first thing a new user sees is the grid they will read every morning, so
/// the animation teaches the interface instead of just entertaining.
public struct DotBloom: View {
    private let columns: Int
    private let rows: Int
    private let accentEvery: Int
    private let dotSize: CGFloat

    @State private var filled = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(columns: Int = 7, rows: Int = 5, accentEvery: Int = 9, dotSize: CGFloat = 14) {
        self.columns = columns
        self.rows = rows
        self.accentEvery = accentEvery
        self.dotSize = dotSize
    }

    private var total: Int { columns * rows }

    public var body: some View {
        VStack(spacing: Space.x1) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: Space.x1) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Circle()
                            .fill(colour(at: index, isFilled: index < filled))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(index < filled ? 1 : 0.55)
                            .animation(
                                .spring(response: 0.42, dampingFraction: 0.7)
                                    .delay(Double(index % columns) * 0.02),
                                value: filled
                            )
                    }
                }
            }
        }
        .task {
            // Respect Reduce Motion by showing the finished state rather than
            // animating into it.
            guard !reduceMotion else { filled = total; return }
            for step in 0...total {
                try? await Task.sleep(for: .milliseconds(38))
                filled = step
            }
        }
    }

    private func colour(at index: Int, isFilled: Bool) -> Color {
        guard isFilled else { return LifeOSTokens.onGradient.opacity(0.16) }
        return index % accentEvery == 0
            ? LifeOSTokens.accent
            : LifeOSTokens.onGradient.opacity(0.92)
    }
}

/// Staged entrance for stacked content: each child fades and rises in turn.
/// Used so an onboarding page assembles itself rather than appearing at once.
public struct StaggeredAppear<Content: View>: View {
    private let index: Int
    private let content: Content
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    public var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Space.x2)
            .task {
                guard !reduceMotion else { shown = true; return }
                try? await Task.sleep(for: .milliseconds(90 * index))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { shown = true }
            }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [ModuleHue.body.top, ModuleHue.body.bottom],
                       startPoint: .top, endPoint: .bottom)
        DotBloom()
    }
    .ignoresSafeArea()
}
