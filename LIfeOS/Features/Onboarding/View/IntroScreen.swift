import SwiftUI
import DesignSystem

/// A single persistent 3D scene accompanies the four-page introduction.
struct IntroScreen: View {
    let onStart: () -> Void
    var onSignIn: (() -> Void)?
    @State private var page = 0
    @State private var visible = false
    @State private var measuredCopyHeight: CGFloat = 206
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 36
    @ScaledMetric(relativeTo: .body) private var copyHeight = 206

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var canvas: Color { LifeOSTokens.canvas.resolve(scheme) }
    private var pageHeight: CGFloat { max(copyHeight, measuredCopyHeight) }
    private let pages = IntroPage.all

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    hero(height: min(320, max(180, geometry.size.height - pageHeight - 260)))

                    if dynamicTypeSize.isAccessibilitySize {
                        // A continuous reading surface at larger sizes avoids a
                        // nested pager competing with vertical accessibility scrolling.
                        pageBody(pages[page])
                    } else {
                        TabView(selection: $page) {
                            ForEach(pages) { item in
                                pageBody(item)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .tag(item.id)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: pageHeight)
                    }

                    pageDots
                        .padding(.top, Space.x1)
                        .padding(.bottom, Space.x2)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .background(canvas.ignoresSafeArea())
        }
        .onChange(of: dynamicTypeSize) { _, _ in measuredCopyHeight = 0 }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var header: some View {
        HStack {
            HStack(spacing: Space.x1) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(LifeOSTokens.accent)
                Text("LifeOS")
                    .tracking(-0.5)
                    .fixedSize()
            }
            .font(.title3.weight(.bold))
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Skip") { onStart() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("Go to account setup")
        }
        .foregroundStyle(ink)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Space.x4)
        .padding(.top, Space.x1)
    }

    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(ink.opacity(scheme == .dark ? 0.12 : 0.08))
                .frame(width: 154, height: 18)
                .blur(radius: 12)
                .padding(.bottom, height * 0.09)
            OnboardingCat(page: page, isActive: visible && scenePhase == .active)
                .frame(maxWidth: 420)
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    private func pageBody(_ item: IntroPage) -> some View {
        VStack(spacing: Space.x2) {
            Text(item.category)
                .font(.caption.weight(.medium))
                .tracking(2)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .padding(.bottom, Space.half)

            Text(item.headline)
                .font(.system(size: headlineSize, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(item.body)
                .font(.subheadline)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.x4)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if height > measuredCopyHeight { measuredCopyHeight = height }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 0) {
            ForEach(pages) { item in
                Button { select(item.id) } label: {
                    Circle()
                        .fill(page == item.id ? LifeOSTokens.accent : LifeOSTokens.dotMissed.resolve(scheme))
                        .frame(width: 6, height: 6)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(item.category), page \(item.id + 1) of \(pages.count)")
                .accessibilityAddTraits(page == item.id ? [.isSelected] : [])
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Space.x1) {
            Button {
                if page == pages.count - 1 { onStart() }
                else { select(page + 1) }
            } label: {
                HStack {
                    Text(page == pages.count - 1 ? "Let’s get started" : "Continue")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(LifeOSTokens.accent)
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, Space.x3)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(canvas)
                .background(ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            .accessibilityHint(page == pages.count - 1 ? "Go to account setup" : "Next introduction page")

            if let onSignIn {
                Button(action: onSignIn) {
                    (Text("Already have an account? ").foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                     + Text("Sign in").foregroundStyle(LifeOSTokens.accent).bold())
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.top, Space.x2)
        .padding(.bottom, Space.x2)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(canvas)
    }

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { page = index }
    }
}

#Preview {
    IntroScreen(onStart: {}, onSignIn: {})
}
