import SwiftUI
import DesignSystem
import Integrations

/// The pitch. Four pages, one per life domain, on the same gradient canvas the
/// rest of the app uses, so the product explains itself by looking like itself.
struct IntroScreen: View {
    let onStart: () -> Void
    var onSignIn: (() -> Void)?
    var onSkipAuth: (() -> Void)?
    @State private var page = 0
    @Environment(\.colorScheme) private var scheme

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
                    if let onSignIn {
                        Button("I already have an account") { onSignIn() }
                            .font(LifeOSType.rowTitle)
                            .foregroundStyle(LifeOSTokens.accent)
                            .frame(height: Space.x5)
                    }
                    if let onSkipAuth {
                        Button("Skip for now") { onSkipAuth() }
                            .font(LifeOSType.secondary.weight(.medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                            .frame(height: Space.x5)
                    } else {
                        Button("Skip") { onStart() }
                            .font(LifeOSType.secondary.weight(.medium))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
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
            //
            // The first page adds the cat in front of it: the grid is the
            // product, but a screen that opens on a bare grid opens on a
            // spreadsheet. The cat greets, the grid explains, and putting the
            // grid behind rather than beside keeps the page to one focal point.
            Group {
                if item.id == 0 {
                    // The cat IS the grid on this page: it is drawn from the
                    // same dots at the same pitch, waving. A `DotBloom` behind
                    // it was two dot fields on different pitches fighting, and
                    // the loose dots read as artefacts on the cat's body.
                    ScanlineCat(style: .dots)
                        .frame(maxWidth: 232)
                } else {
                    DotBloom(accentEvery: item.id + 5)
                        .id(item.id)      // restart the bloom on each page
                }
            }
            .frame(maxHeight: item.id == 0 ? 224 : 180)

            VStack(alignment: .leading, spacing: Space.x2) {
                StaggeredAppear(index: 1) {
                    Text(item.headline)
                        .font(LifeOSType.display)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                StaggeredAppear(index: 2) {
                    Text(item.body)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
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
                    .fill(index == page
                          ? LifeOSTokens.primaryText.resolve(scheme)
                          : LifeOSTokens.dotMissed.resolve(scheme))
                    .frame(width: index == page ? Space.x3 : Space.x1, height: Space.x1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            }
        }
    }
}

#Preview {
    IntroScreen(onStart: {}, onSignIn: {})
}
