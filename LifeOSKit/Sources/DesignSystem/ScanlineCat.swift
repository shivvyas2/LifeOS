import SwiftUI

/// A cat drawn entirely as horizontal scanlines, waving.
///
/// The intro's greeting. `DotBloom` teaches the interface; this gives the first
/// screen a face, in the same ink and on the same grid, so it reads as part of
/// the app rather than as a sticker dropped on top of it.
///
/// All geometry lives in `ScanlineCatSilhouette` and `ScanlineSlicer`, which
/// are pure and tested. This view only decides colour, timing and how the cat
/// assembles on appear.
public enum ScanlineCatStyle: Sendable {
    /// Horizontal strokes, closest to the reference image.
    case lines
    /// The same rows, drawn as dots on the app's grid pitch, so the cat is made
    /// of the very thing the rest of the product is made of.
    case dots
}

public struct ScanlineCat: View {
    private let lineCount: Int
    private let seed: UInt64
    private let period: Double
    private let style: ScanlineCatStyle

    @State private var appeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - lineCount: scanline budget. Higher reads as a photocopy, lower as a
    ///     woodcut; 46 is the point where the eye still resolves a cat.
    ///   - seed: fixes the ragged line ends, so the same cat redraws identically.
    ///   - period: seconds for one full wave.
    ///   - style: lines like the reference, or dots like the rest of the app.
    public init(
        style: ScanlineCatStyle = .dots,
        lineCount: Int = 34,
        seed: UInt64 = 20260825,
        period: Double = 2.4
    ) {
        self.style = style
        self.lineCount = lineCount
        self.seed = seed
        self.period = period
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = wave(at: timeline.date)
                // The whole cat lifts a little as the paw goes up. Tiny — under
                // one percent of the height — but it is the difference between
                // a waving arm and a waving cat.
                let bob = size.height * 0.008 * (1 - cos(phase * 2 * .pi)) / 2
                let box = CGRect(origin: .zero, size: size).offsetBy(dx: 0, dy: -bob)
                let shapes = ScanlineCatSilhouette.shapes(in: box)
                let segments = ScanlineSlicer.segments(
                    for: shapes,
                    in: box,
                    lineCount: lineCount,
                    seed: seed
                )

                let pitch = size.height / CGFloat(lineCount)

                for (index, segment) in segments.enumerated() {
                    // On appear each row slides in from the side it is nearest,
                    // so the cat resolves out of drifting rows instead of
                    // simply fading up. The offset is per row, which is what
                    // makes it read as a scan rather than as a slide.
                    let drift = self.drift(row: index, size: size)
                    let tint = ink.opacity(appeared || reduceMotion ? 1 : 0)

                    switch style {
                    case .lines:
                        var path = Path()
                        path.move(to: CGPoint(x: segment.xStart + drift, y: segment.y))
                        path.addLine(to: CGPoint(x: segment.xEnd + drift, y: segment.y))
                        context.stroke(
                            path,
                            with: .color(tint),
                            style: StrokeStyle(lineWidth: segment.weight, lineCap: .butt)
                        )

                    case .dots:
                        // One dot pitch across as well as down, so the cat sits
                        // on a square grid rather than on stripes of dots.
                        let centres = ScanlineSlicer.dots(
                            along: segment.xStart...segment.xEnd,
                            spacing: pitch
                        )
                        // The row's stroke weight becomes the dot's diameter,
                        // so the banding that shaded the line drawing now shows
                        // up as heavier and lighter dots.
                        let diameter = min(segment.weight * 1.35, pitch * 0.95)
                        for centre in centres {
                            let dot = CGRect(
                                x: centre + drift - diameter / 2,
                                y: segment.y - diameter / 2,
                                width: diameter,
                                height: diameter
                            )
                            context.fill(Path(ellipseIn: dot), with: .color(tint))
                        }
                    }
                }

                // The face goes on last and solid. Everything above it is
                // striped, so a solid block is the only mark that can still
                // read as an eye.
                if appeared || reduceMotion {
                    // Blush first, under the eyes: it is a wash on the cheek,
                    // not a sticker on top of the face.
                    for cheek in ScanlineCatSilhouette.blush(in: box) {
                        context.fill(
                            Path(ellipseIn: cheek),
                            with: .color(LifeOSTokens.accent.opacity(0.5))
                        )
                    }

                    // The blink: the eye keeps its width and loses its height,
                    // which is what a real lid does. Scaling both would read as
                    // the eye shrinking away.
                    let openness = ScanlineCatSilhouette.eyeOpenness(at: phase)
                    for eye in ScanlineCatSilhouette.eyes(in: box) {
                        let lid = CGRect(
                            x: eye.minX,
                            y: eye.midY - eye.height * openness / 2,
                            width: eye.width,
                            height: max(eye.height * openness, eye.height * 0.08)
                        )
                        context.fill(Path(ellipseIn: lid), with: .color(ink))
                    }
                    // The catchlight is punched in the canvas colour rather
                    // than white, so it still reads as a highlight in dark mode.
                    // The catchlight goes with the lid: a highlight floating on
                    // a shut eye is the kind of detail that reads as a bug.
                    if openness > 0.55 {
                        for highlight in ScanlineCatSilhouette.eyeHighlights(in: box) {
                            context.fill(
                                Path(ellipseIn: highlight),
                                with: .color(LifeOSTokens.canvas.resolve(scheme))
                            )
                        }
                    }

                    let nose = ScanlineCatSilhouette.nose(in: box)
                    context.fill(
                        Path(roundedRect: nose, cornerRadius: nose.height * 0.4),
                        with: .color(ink)
                    )

                    let mouth = ScanlineCatSilhouette.mouth(in: box)
                    var smile = Path()
                    smile.move(to: mouth.start)
                    smile.addQuadCurve(to: mouth.end, control: mouth.control)
                    context.stroke(
                        smile,
                        with: .color(ink),
                        style: StrokeStyle(lineWidth: max(1.5, size.height * 0.008), lineCap: .round)
                    )
                }
            }
        }
        .task {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.easeOut(duration: 0.9)) { appeared = true }
        }
        // Decorative. The headline beside it already says what the screen is,
        // and "waving cat illustration" in the middle of the pitch would be
        // one more stop between the user and the button.
        .accessibilityHidden(true)
    }

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    /// Position in the wave cycle, from a wall clock rather than from stored
    /// state, so the animation costs nothing when the view is off screen.
    private func wave(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0.5 }
        let seconds = date.timeIntervalSinceReferenceDate
        return CGFloat((seconds.truncatingRemainder(dividingBy: period)) / period)
    }

    /// How far this row is still from home. Zero once the entrance is done.
    private func drift(row: Int, size: CGSize) -> CGFloat {
        guard !appeared, !reduceMotion else { return 0 }
        let direction: CGFloat = row.isMultiple(of: 2) ? -1 : 1
        return direction * size.width * 0.22
    }
}

#Preview("Dots") {
    ScanlineCat(style: .dots)
        .frame(width: 220, height: 260)
        .padding()
        .background(LifeOSTokens.canvas.light)
}

#Preview("Lines") {
    ScanlineCat(style: .lines, lineCount: 46)
        .frame(width: 220, height: 260)
        .padding()
        .background(LifeOSTokens.canvas.light)
}

#Preview("Dark") {
    ScanlineCat()
        .frame(width: 220, height: 260)
        .padding()
        .background(LifeOSTokens.canvas.dark)
        .preferredColorScheme(.dark)
}
