import SwiftUI
import DesignSystem
import Integrations

/// The pitch. Four pages, one per life domain, on the same gradient canvas the
/// rest of the app uses, so the product explains itself by looking like itself.
struct IntroScreen: View {
    let onStart: () -> Void
    var onSkipAuth: (() -> Void)?
    @State private var page = 0

    var body: some View {
        let pages = IntroPage.all

        GradientCanvas(hue: pages[page].hue) {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages) { item in
                        pageBody(item)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots(count: pages.count)
                    .padding(.bottom, Space.x3)

                VStack(spacing: Space.x1) {
                    PrimaryButton(page == pages.count - 1 ? "Get started" : "Continue") {
                        if page == pages.count - 1 {
                            onStart()
                        } else {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 }
                        }
                    }
                    if let onSkipAuth {
                        Button("Skip for now") { onSkipAuth() }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LifeOSTokens.onGradient.opacity(0.75))
                            .frame(height: Space.x5)
                    } else {
                        Button("Skip") { onStart() }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LifeOSTokens.onGradient.opacity(0.75))
                            .frame(height: Space.x5)
                    }
                }
                .padding(.horizontal, Space.x3)
                .padding(.bottom, Space.x4)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: page)
    }

    private func pageBody(_ item: IntroPage) -> some View {
        VStack(spacing: Space.x5) {
            Spacer(minLength: Space.x4)

            // The dot grid is the app's central motif, so the intro animates it
            // rather than showing an unrelated illustration.
            DotBloom(accentEvery: item.id + 5)
                .id(item.id)          // restart the bloom on each page
                .frame(maxHeight: 180)

            VStack(alignment: .leading, spacing: Space.x2) {
                StaggeredAppear(index: 1) {
                    Text(item.headline)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(LifeOSTokens.onGradient)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StaggeredAppear(index: 2) {
                    Text(item.body)
                        .font(.system(size: 16))
                        .foregroundStyle(LifeOSTokens.onGradient.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.x3)

            Spacer(minLength: 0)
        }
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: Space.x1) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(LifeOSTokens.onGradient.opacity(index == page ? 1 : 0.35))
                    .frame(width: index == page ? Space.x3 : Space.x1, height: Space.x1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            }
        }
    }
}

#Preview {
    IntroScreen(onStart: {})
}
