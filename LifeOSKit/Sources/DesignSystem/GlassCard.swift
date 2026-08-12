import SwiftUI

/// Frosted card, for use while over the saturated region of a gradient.
///
/// The material costs an offscreen pass, so this is screen furniture only:
/// never the content of a repeated cell, and never nested inside a `SolidCard`.
public struct GlassCard<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Solid card, for use once the gradient has faded to near-white.
///
/// Same rule as `GlassCard`: the shadow is an offscreen pass, so this is
/// per-screen furniture, not cell content.
public struct SolidCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.05), radius: 12, y: 4)
            )
    }
}
