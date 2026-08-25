import SwiftUI

/// Frosted card used on Health and Settings. Material, not a solid box,
/// so the canvas gradient stays visible through it.
public struct GlassPanel<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(scheme == .dark ? 0.14 : 0.5),
                                lineWidth: 1
                            )
                    }
            )
    }
}
