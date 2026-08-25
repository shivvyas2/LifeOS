import SwiftUI

/// The one card. White, rounded, soft-shadowed on the light canvas; a tonal
/// step up from the background in dark mode, where a shadow buys nothing.
///
/// The shadow is an offscreen pass, so this is screen furniture: never the
/// content of a long repeated list cell (use `tileSurface` rows for those).
public struct SoftCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow,
                            radius: 12, y: 4)
            )
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
