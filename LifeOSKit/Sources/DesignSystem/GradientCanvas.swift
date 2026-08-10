import SwiftUI

/// The one gradient primitive. Saturated at the top, near-white at the bottom.
/// Adding a module later is a hue token, not a new screen design.
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
            LinearGradient(
                colors: scheme == .dark
                    ? [hue.darkTop, hue.darkBottom]
                    : [hue.top, hue.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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
                        .foregroundStyle(.white)
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
                        .foregroundStyle(.white)
                        .padding(.top, 60)
                }
                .frame(width: 200, height: 420)
            }
        }
    }
    .preferredColorScheme(.dark)
}
