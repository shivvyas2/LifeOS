import SwiftUI

/// The one card. White, rounded, soft-shadowed on the light canvas; a tonal
/// step up from the background in dark mode, where a shadow buys nothing.
///
/// The shadow is an offscreen pass, so this is screen furniture: never the
/// content of a long repeated list cell (use `tileSurface` rows for those).
public struct SoftCard<Content: View>: View {
    private let content: Content
    private let hue: ModuleHue?
    @Environment(\.colorScheme) private var scheme

    public init(hue: ModuleHue? = nil, @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            // Paper with a hairline edge in the editorial style. `hue` no
            // longer tints the card: a pastel per module was what made each
            // screen look like its own app. It is kept so callers compile.
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Editorial.rule(scheme)))
    }
}

#Preview("Light") {
    ZStack {
        LifeOSTokens.canvas.resolve(.light).ignoresSafeArea()
        SoftCard {
            Text("Soft card")
                .foregroundStyle(LifeOSTokens.primaryText.resolve(.light))
        }
        .padding()
    }
}

#Preview("Dark") {
    ZStack {
        LifeOSTokens.canvas.resolve(.dark).ignoresSafeArea()
        SoftCard {
            Text("Soft card")
                .foregroundStyle(LifeOSTokens.primaryText.resolve(.dark))
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
