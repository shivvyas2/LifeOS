import SwiftUI

/// The one canvas primitive. Flat and near-neutral, with a whisper of the
/// module's hue washed in at the top. Adding a module later is a hue token,
/// not a new screen design.
public struct GradientCanvas<Content: View>: View {
    private let hue: ModuleHue
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(hue: ModuleHue, @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()

            // A whisper of the module's identity at the top. The hue survives
            // the restyle as a tint, not a paint job.
            LinearGradient(
                colors: [(scheme == .dark ? hue.pastelDark : hue.pastel).opacity(scheme == .dark ? 0.7 : 0.55),
                         .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .ignoresSafeArea(edges: .top)

            content
        }
    }
}

#Preview("All hues, light") {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(ModuleHue.allCases, id: \.self) { hue in
                GradientCanvas(hue: hue) {
                    Text(hue.rawValue)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(.light))
                        .padding(.top, 60)
                }
                .frame(width: 200, height: 420)
            }
        }
    }
}

#Preview("All hues, dark") {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(ModuleHue.allCases, id: \.self) { hue in
                GradientCanvas(hue: hue) {
                    Text(hue.rawValue)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(.dark))
                        .padding(.top, 60)
                }
                .frame(width: 200, height: 420)
            }
        }
    }
    .preferredColorScheme(.dark)
}
