import SwiftUI
import DesignSystem

/// The first-run walkthrough: one page per part of the app, shown once,
/// right after the first sign-in (or skip) lands in the app.
///
/// Drawn in the app's own ink: the cat and the blooming month open it, and
/// every section's motif assembles out of dots on the same grid pitch,
/// because that vocabulary IS the product. No pastel washes, no stock
/// symbol-in-a-circle; the intro set that standard and this keeps it.
struct FirstRunTour: View {
    var onDone: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var page = 0

    private static let pages: [TourPage] = [
        TourPage(
            motif: .cat,
            title: "Every day, a dot",
            body: "The month on Today fills in as you live it. Tap any dot to see that day's schedule, habits and numbers."
        ),
        TourPage(
            motif: .symbol("heart.fill"),
            title: "Health, in one place",
            body: "Steps, sleep, weight and recovery arrive from your watch, Whoop and scale, and read together instead of across four apps."
        ),
        TourPage(
            motif: .symbol("dollarsign"),
            title: "Money that explains itself",
            body: "Connect a bank and the month sorts itself into budgets, with unclaimed spending called out until it has a home."
        ),
        TourPage(
            motif: .symbol("books.vertical.fill"),
            title: "A library for your life",
            body: "Pages filed the PARA way: projects, areas, resources and archive. Your habits live here too."
        ),
        TourPage(
            motif: .symbol("square.grid.2x2.fill"),
            title: "Score your life",
            body: "Eight life sectors, closed once a month. The board shows where life is strong and where it wants your attention."
        ),
        TourPage(
            motif: .symbol("bubble.left.and.bubble.right.fill"),
            title: "Two assistants",
            body: "LIFO reads your health and talks it through with you. The calendar assistant reads your day and can move it. Both live on Today."
        ),
    ]

    var body: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: onDone)
                        .font(LifeOSType.secondary.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .padding(.trailing, 24)
                        .padding(.top, 12)
                }

                TabView(selection: $page) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, tourPage in
                        pageView(tourPage, active: page == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, 24)

                PrimaryButton(page == Self.pages.count - 1 ? "Start" : "Continue") {
                    if page == Self.pages.count - 1 {
                        onDone()
                    } else {
                        withAnimation(.spring(duration: 0.45)) { page += 1 }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func pageView(_ tourPage: TourPage, active: Bool) -> some View {
        VStack(spacing: 30) {
            Spacer()

            Group {
                switch tourPage.motif {
                case .cat:
                    // The intro's pairing, kept verbatim: the cat waving over
                    // the month blooming in, both on the same grid.
                    VStack(spacing: 26) {
                        ScanlineCat(style: .dots)
                            .frame(width: 190, height: 190)
                        DotBloom()
                    }
                case .symbol(let name):
                    DotMatrixSymbol(symbol: name, active: active)
                        .frame(width: 200, height: 200)
                }
            }
            .opacity(active ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: active)

            VStack(spacing: 12) {
                Text(tourPage.title)
                    .font(LifeOSType.screenTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .multilineTextAlignment(.center)

                Text(tourPage.body)
                    .font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(y: active ? 0 : 16)
            .opacity(active ? 1 : 0)
            .animation(.spring(duration: 0.5).delay(0.08), value: active)

            Spacer()
            Spacer()
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == page
                          ? LifeOSTokens.accent
                          : LifeOSTokens.secondaryText.resolve(scheme).opacity(0.25))
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(.spring(duration: 0.35), value: page)
            }
        }
    }
}

private struct TourPage {
    enum Motif {
        case cat
        case symbol(String)
    }

    let motif: Motif
    let title: String
    let body: String
}

/// An SF Symbol assembled out of dots on the app's grid pitch.
///
/// A dense field of circles staggers in the way `DotBloom` fills, and the
/// symbol's own shape masks the field, so a heart or a dollar sign appears
/// made of the same material as the month grid. Ink with the occasional
/// accent dot, exactly like the grid it echoes.
private struct DotMatrixSymbol: View {
    let symbol: String
    var active: Bool

    private let columns = 16
    private let rows = 16
    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 4.5

    @State private var filled = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int { columns * rows }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Circle()
                            .fill(colour(at: index))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(index < filled ? 1 : 0.4)
                            .opacity(index < filled ? 1 : 0)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.7)
                                    .delay(Double(index % columns) * 0.012),
                                value: filled
                            )
                    }
                }
            }
        }
        .mask {
            Image(systemName: symbol)
                .font(LifeOSType.numeral(150, weight: .bold))
        }
        .task(id: active) {
            guard active else { filled = 0; return }
            guard !reduceMotion else { filled = total; return }
            filled = 0
            // Row by row, the way the month blooms. Two rows per step keeps
            // the whole assembly under a second without losing the sweep.
            for step in stride(from: 0, through: total, by: columns * 2) {
                try? await Task.sleep(for: .milliseconds(55))
                filled = step
            }
            filled = total
        }
    }

    private func colour(at index: Int) -> Color {
        index % 11 == 0
            ? LifeOSTokens.accent
            : LifeOSTokens.primaryText.resolve(scheme)
    }
}

#Preview {
    FirstRunTour(onDone: {})
}
