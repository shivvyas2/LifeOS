import SwiftUI
import DesignSystem

/// The coach's palette and backdrop.
///
/// Deep navy ground with a cyan core bleeding out through blue. It is the one
/// screen in the app that is dark in both appearances: the aura only reads as
/// light on a dark ground, and inverting it for light mode would produce a
/// washed cyan smear rather than a glow.
enum LifoPalette {
    /// #050A30
    static let night = Color(red: 0.020, green: 0.039, blue: 0.188)
    /// #0000FF
    static let blue = Color(red: 0.0, green: 0.0, blue: 1.0)
    /// #00FFFF
    static let cyan = Color(red: 0.0, green: 1.0, blue: 1.0)

    /// Ink on the aura. Not pure white: at full white the text vibrates
    /// against the cyan, which is the same reason road signs are off-white.
    static let ink = Color(white: 0.96)
    static let quietInk = Color(white: 0.96).opacity(0.62)
}

/// The glow behind the coach.
///
/// Three stacked radial gradients rather than one: a single ramp from cyan to
/// navy passes through a muddy teal in the middle, and the reference glow gets
/// its depth from a small saturated core sitting inside a much larger, much
/// softer blue wash.
///
/// It breathes, slowly. A still gradient reads as a wallpaper; a moving one
/// reads as something listening. The motion is deliberately below the rate
/// anyone would call an animation, and it stops dead for Reduce Motion.
struct LifoAura: View {
    /// 0...1, driven by the mic level while listening so the core answers the
    /// voice. At rest it simply breathes.
    var intensity: CGFloat = 0
    var isActive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            // The core swells with the voice, and breathes when idle.
            let swell = 1 + (isActive ? intensity * 0.35 : 0) + breath * 0.06

            ZStack {
                LifoPalette.night

                // The far wash: most of the screen, barely there.
                RadialGradient(
                    colors: [LifoPalette.blue.opacity(0.55), LifoPalette.night.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.62 * swell
                )

                // The body of the glow.
                RadialGradient(
                    colors: [LifoPalette.blue.opacity(0.85), LifoPalette.blue.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.34 * swell
                )

                // The core. Small and saturated: this is the only place the
                // cyan appears at full strength, which is what keeps it a
                // light source rather than a colour.
                RadialGradient(
                    colors: [LifoPalette.cyan.opacity(0.9),
                             LifoPalette.cyan.opacity(0.25),
                             LifoPalette.cyan.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.16 * swell
                )
                .blur(radius: 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.35), value: intensity)
        }
        .ignoresSafeArea()
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                breath = 1
            }
        }
    }
}

#Preview {
    LifoAura(intensity: 0.3, isActive: true)
}
