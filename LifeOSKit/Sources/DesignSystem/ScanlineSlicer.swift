import CoreGraphics

/// A primitive the scanline renderer can cut through analytically.
///
/// Deliberately not `Path`. A `Path` can draw anything but cannot answer "which
/// x-ranges are you covering at this y", and that question is the entire
/// algorithm. Three primitives are enough to build a cat, and each one answers
/// the question in closed form, so slicing costs no rasterisation.
public enum ScanlineShape: Equatable, Sendable {
    case ellipse(center: CGPoint, radii: CGSize)
    case rect(CGRect)
    case triangle(CGPoint, CGPoint, CGPoint)
}

/// Cuts shapes into horizontal spans.
///
/// Pure, synchronous and free of SwiftUI on purpose: the view above it is a
/// `Canvas` that can only be checked by eye, so everything that can be decided
/// by arithmetic is decided here, where a test can reach it.
public enum ScanlineSlicer {

    /// The x-ranges covered at one scan height, merged and ordered left to right.
    ///
    /// Overlaps merge because two shapes meeting on a row are one stroke of ink,
    /// not two abutting strokes with a seam. Gaps survive because a gap is
    /// meaningful: it is the daylight between the two feet and between the
    /// raised paw and the body.
    public static func spans(of shapes: [ScanlineShape], at y: CGFloat) -> [ClosedRange<CGFloat>] {
        let raw = shapes.compactMap { span(of: $0, at: y) }
        guard !raw.isEmpty else { return [] }

        let sorted = raw.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<CGFloat>] = [sorted[0]]

        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.lowerBound <= last.upperBound {
                // Touching counts as overlapping. Two spans that share an edge
                // would otherwise draw as one line with an invisible join that
                // shows up the moment either side gets a different weight.
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// One shape's coverage at one height, or `nil` where it does not reach.
    ///
    /// A row that only grazes a shape returns `nil` rather than a zero-width
    /// range: the tangent row of every ellipse would otherwise leave a hairline
    /// stub floating above the head and below the feet.
    private static func span(of shape: ScanlineShape, at y: CGFloat) -> ClosedRange<CGFloat>? {
        switch shape {
        case let .ellipse(center, radii):
            guard radii.width > 0, radii.height > 0 else { return nil }
            let dy = (y - center.y) / radii.height
            guard abs(dy) < 1 else { return nil }
            let halfWidth = radii.width * (1 - dy * dy).squareRoot()
            guard halfWidth > 0 else { return nil }
            return (center.x - halfWidth)...(center.x + halfWidth)

        case let .rect(rect):
            guard rect.width > 0, rect.height > 0 else { return nil }
            guard y >= rect.minY, y <= rect.maxY else { return nil }
            return rect.minX...rect.maxX

        case let .triangle(a, b, c):
            let crossings = [(a, b), (b, c), (c, a)].compactMap { edge in
                crossing(of: edge.0, edge.1, at: y)
            }
            guard let low = crossings.min(), let high = crossings.max(), high > low else { return nil }
            return low...high
        }
    }

    /// Where a horizontal line at `y` crosses one edge, if it crosses at all.
    ///
    /// The half-open `y0..<y1` test is what stops a vertex being counted twice:
    /// a horizontal cut exactly through a shared corner belongs to the edge
    /// below it, never to both edges meeting there.
    private static func crossing(of start: CGPoint, _ end: CGPoint, at y: CGFloat) -> CGFloat? {
        let (low, high) = start.y <= end.y ? (start, end) : (end, start)
        guard y >= low.y, y < high.y, high.y > low.y else { return nil }
        let t = (y - low.y) / (high.y - low.y)
        return low.x + t * (high.x - low.x)
    }
}

/// One stroke of the raster: a horizontal run of ink at a fixed height.
public struct ScanlineSegment: Equatable, Sendable {
    public let y: CGFloat
    public let xStart: CGFloat
    public let xEnd: CGFloat
    /// Stroke thickness. Varying it per row is what produces the dense bands
    /// that read as shading rather than as a barcode.
    public let weight: CGFloat

    public init(y: CGFloat, xStart: CGFloat, xEnd: CGFloat, weight: CGFloat) {
        self.y = y
        self.xStart = xStart
        self.xEnd = xEnd
        self.weight = weight
    }
}

extension ScanlineSlicer {

    /// Every stroke needed to draw `shapes` as scanlines inside `rect`.
    ///
    /// `lineCount` is a budget rather than a promise: rows that fall above the
    /// ears or below the feet contribute nothing. `seed` fixes the jitter, so
    /// the same cat redraws identically across view updates instead of
    /// shimmering every time an unrelated `@State` changes.
    public static func segments(
        for shapes: [ScanlineShape],
        in rect: CGRect,
        lineCount: Int,
        seed: UInt64
    ) -> [ScanlineSegment] {
        guard lineCount > 0, !shapes.isEmpty, rect.height > 0, rect.width > 0 else { return [] }

        let pitch = rect.height / CGFloat(lineCount)
        var result: [ScanlineSegment] = []

        for row in 0..<lineCount {
            // Half a pitch of inset keeps the first and last rows inside the
            // frame instead of straddling its edge.
            let y = rect.minY + (CGFloat(row) + 0.5) * pitch
            let spans = spans(of: shapes, at: y)
            guard !spans.isEmpty else { continue }

            let rowNoise = noise(seed: seed, row: row, index: 0)
            // 0.34...0.92 of the pitch. The floor keeps a light row visible;
            // the ceiling keeps a heavy row from closing the gap to its
            // neighbour and turning the raster into a solid block.
            let weight = pitch * (0.34 + 0.58 * rowNoise)

            for (index, span) in spans.enumerated() {
                let ragged = ragged(span, pitch: pitch, seed: seed, row: row, index: index + 1)
                let start = max(rect.minX, ragged.lowerBound)
                let end = min(rect.maxX, ragged.upperBound)
                // A span the jitter collapsed to nothing is a stroke with no
                // length. Dropping it is what keeps `xEnd > xStart` true for
                // every segment the caller receives.
                guard end - start > 0.5 else { continue }
                result.append(ScanlineSegment(y: y, xStart: start, xEnd: end, weight: weight))
            }
        }
        return result
    }

    /// Pulls each end of a span in or out by up to about half a row.
    ///
    /// This is the whole difference between a photocopied look and a clean
    /// vector silhouette: real scanline art has ends that overshoot and fall
    /// short of the true edge.
    private static func ragged(
        _ span: ClosedRange<CGFloat>,
        pitch: CGFloat,
        seed: UInt64,
        row: Int,
        index: Int
    ) -> ClosedRange<CGFloat> {
        let reach = pitch * 0.9
        let head = (noise(seed: seed, row: row, index: index &* 31) - 0.5) * reach
        let tail = (noise(seed: seed, row: row, index: index &* 57) - 0.5) * reach
        let lower = span.lowerBound + head
        let upper = span.upperBound + tail
        guard upper > lower else { return span }
        return lower...upper
    }

    /// Deterministic 0...1 noise from a seed and a position.
    ///
    /// SplitMix64 rather than `Double.random`: the cat must redraw identically
    /// for a given seed, and a system RNG would reshuffle every stroke on every
    /// single body evaluation.
    private static func noise(seed: UInt64, row: Int, index: Int) -> CGFloat {
        var state = seed &+ UInt64(bitPattern: Int64(row)) &* 0x9E3779B97F4A7C15
        state = state &+ UInt64(bitPattern: Int64(index)) &* 0xBF58476D1CE4E5B9
        state = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
        state = (state ^ (state >> 27)) &* 0x94D049BB133111EB
        state = state ^ (state >> 31)
        return CGFloat(state >> 11) / CGFloat(UInt64(1) << 53)
    }
}

extension ScanlineSlicer {

    /// Dot centres along one run of ink.
    ///
    /// The dot rendering of the cat is not decoration: `DotGrid` and `DotBloom`
    /// are the app's motif, so a cat built from the same dots belongs to the
    /// product in a way a line drawing never quite does.
    ///
    /// Centred rather than left-aligned, because a run that starts hard at its
    /// left edge and stops short on the right makes every row lean the same way.
    public static func dots(along run: ClosedRange<CGFloat>, spacing: CGFloat) -> [CGFloat] {
        guard spacing > 0 else { return [] }
        let length = run.upperBound - run.lowerBound
        guard length >= 0 else { return [] }

        // A run shorter than one dot pitch is still ink: the ear tips and the
        // toes are precisely the short runs, and dropping them shaves the
        // silhouette down to a blob.
        let count = max(1, Int((length / spacing).rounded(.down)) + 1)
        let span = CGFloat(count - 1) * spacing
        let start = run.lowerBound + (length - span) / 2
        return (0..<count).map { start + CGFloat($0) * spacing }
    }
}
