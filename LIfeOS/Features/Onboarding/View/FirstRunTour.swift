import SwiftUI
import DesignSystem

/// The first-run walkthrough: one page per part of the app, shown once,
/// right after the first sign-in (or skip) lands in the app.
///
/// Each page is a hue-washed canvas with a big pastel glyph that springs in,
/// a title, and two sentences of what the section does. Deliberately short:
/// six pages, one idea each, and a Skip that is always visible. A tour that
/// cannot be escaped teaches resentment, not the app.
struct FirstRunTour: View {
    var onDone: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var page = 0

    private static let pages: [TourPage] = [
        TourPage(
            hue: .habits, icon: "circle.grid.3x3.fill",
            title: "Every day, a dot",
            body: "The month on Today fills in as you live it. Tap any dot to see that day's schedule, habits and numbers."
        ),
        TourPage(
            hue: .recovery, icon: "heart.fill",
            title: "Health, in one place",
            body: "Steps, sleep, weight and recovery arrive from your watch, Whoop and scale, and read together instead of across four apps."
        ),
        TourPage(
            hue: .money, icon: "dollarsign.circle.fill",
            title: "Money that explains itself",
            body: "Connect a bank and the month sorts itself into budgets, with unclaimed spending called out until it has a home."
        ),
        TourPage(
            hue: .nutrition, icon: "books.vertical.fill",
            title: "A library for your life",
            body: "Pages filed the PARA way: projects, areas, resources and archive. Your habits live here too."
        ),
        TourPage(
            hue: .body, icon: "square.grid.2x2.fill",
            title: "Score your life",
            body: "Eight life sectors, closed once a month. The board shows where life is strong and where it wants your attention."
        ),
        TourPage(
            hue: .activity, icon: "bubble.left.and.bubble.right.fill",
            title: "Two assistants",
            body: "LIFO reads your health and talks it through with you. The calendar assistant reads your day and can move it. Both live on Today."
        ),
    ]

    var body: some View {
        let current = Self.pages[page]

        ZStack {
            // The page's hue washes the whole canvas, so swiping the tour
            // previews the way each section colours the app.
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            LinearGradient(
                colors: [
                    (scheme == .dark ? current.hue.pastelDark : current.hue.pastel).opacity(0.85),
                    .clear,
                ],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: page)

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

    private func pageView(_ tourPage: TourPage, active: Bool) -> some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(scheme == .dark ? tourPage.hue.pastelDark : tourPage.hue.pastel)
                    .frame(width: 148, height: 148)
                Image(systemName: tourPage.icon)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(tourPage.hue.top)
                    .symbolEffect(.bounce, value: active)
            }
            .scaleEffect(active ? 1 : 0.7)
            .opacity(active ? 1 : 0)
            .animation(.spring(duration: 0.55, bounce: 0.35), value: active)

            VStack(spacing: 12) {
                Text(tourPage.title)
                    .font(.system(size: 28, weight: .bold))
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
    let hue: ModuleHue
    let icon: String
    let title: String
    let body: String
}

#Preview {
    FirstRunTour(onDone: {})
}
