import SwiftUI
import Soundscape

/// Soft rings that breathe at the music's pace and brighten with it.
/// Still when Reduce Motion is on.
struct FocusVisual: View {
    var parameters: SoundParameters?
    var reading: TimerReading?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || reading?.isPaused == true)) { context in
            Canvas { gc, size in
                let period = parameters?.barSeconds ?? 8
                let t = context.date.timeIntervalSinceReferenceDate
                let breath = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(2 * .pi * t / period)
                let brightness = parameters?.brightness ?? 0.4
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = min(size.width, size.height) / 2
                let ink: Color = scheme == .dark ? .white : .black
                for ring in 0..<5 {
                    let r = base * (0.3 + 0.14 * Double(ring)) * (0.92 + 0.08 * breath)
                    let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
                    let alpha = (0.05 + 0.12 * brightness) * (1 - Double(ring) * 0.15)
                    gc.fill(Path(ellipseIn: rect), with: .color(ink.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
