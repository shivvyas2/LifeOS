import SwiftUI

/// A rolling amplitude history from the microphone or a spoken reply,
/// silent at rest. Forty-eight bars in one colour: ink when idle, the
/// accent while LIFO listens or speaks. This is the whole of the voice
/// screen's visual, in place of the orb that used to fill it.
public struct AudioWaveform: View {
    let level: CGFloat
    let active: Bool
    let color: Color
    @State private var samples = Array(repeating: CGFloat.zero, count: 48)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(level: CGFloat, active: Bool, color: Color) {
        self.level = level; self.active = active; self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            for (index, sample) in samples.enumerated() {
                let height = max(2, sample * (size.height - 4))
                let rect = CGRect(x: CGFloat(index) * size.width / 48, y: (size.height - height) / 2,
                                  width: 2, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.35 + sample * 0.65)))
            }
        }
        .onChange(of: level) { _, value in
            guard !reduceMotion else { return }
            samples.removeFirst()
            samples.append(active && value.isFinite ? min(max(value, 0), 1) : 0)
        }
        .onChange(of: active) { _, active in
            if !active { samples = Array(repeating: 0, count: 48) }
        }
        .accessibilityLabel(active ? "Audio is active" : "Audio is idle")
    }
}
