import SwiftUI

/// The screen dimmed with one view cut out of the dimming, and a card saying
/// what that view is for. Modal: taps outside the card do nothing.
///
/// Expects to be laid out over the whole window with the safe area ignored;
/// `frame` is global and is moved into this view's space here. A nil frame is
/// the moment between steps (a page opening, an anchor not drawn yet): the
/// screen stays dimmed and inert, with no hole and no card.
public struct WalkthroughOverlay: View {
    let step: WalkthroughStep
    let frame: CGRect?
    let isLast: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AccessibilityFocusState private var sentenceFocused: Bool

    public init(step: WalkthroughStep, frame: CGRect?, isLast: Bool,
                onNext: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.step = step
        self.frame = frame
        self.isLast = isLast
        self.onNext = onNext
        self.onSkip = onSkip
    }

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    public var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let cutout = frame?.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8) ?? .zero
            let below = WalkthroughScript.cardSitsBelow(cutout, in: proxy.size.height)

            ZStack {
                ZStack {
                    Rectangle().fill(LifeOSTokens.scrim)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .contentShape(.rect)
                .onTapGesture {}
                .accessibilityHidden(true)

                if frame != nil {
                    card
                        .frame(maxWidth: 360)
                        .padding(.horizontal, Space.x2)
                        .padding(.top, below ? cutout.maxY + Space.x1 : 0)
                        .padding(.bottom, below ? 0 : proxy.size.height - cutout.minY + Space.x1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: frame)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(step.sentence)
                .lifeOSText(.body)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($sentenceFocused)
            HStack {
                Button("Skip", action: onSkip)
                    .buttonStyle(.editorial(.quiet, size: .compact))
                Spacer()
                Button(isLast ? "Done" : "Next", action: onNext)
                    .buttonStyle(.editorial(.primary, size: .compact))
            }
        }
        .padding(Space.x3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LifeOSTokens.cardSurface.resolve(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ink.opacity(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.card")
        // Modal for VoiceOver too: swiping past the card must not reach the
        // controls under the scrim.
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Highlighted: \(step.target)")
        .onAppear { sentenceFocused = true }
        .onChange(of: step) { sentenceFocused = true }
    }
}
