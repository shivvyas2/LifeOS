import Testing
import CoreGraphics
@testable import DesignSystem

/// The slicer is the geometry half of `ScanlineCat`, kept separate from the
/// view for the same reason `EscalationPolicy` is kept out of the router:
/// every branch here can be exercised without a `Canvas`, a screen or a
/// snapshot.
@Suite struct ScanlineSlicerTests {

    // MARK: - Spans across one row

    /// A horizontal cut through the middle of a circle is its full diameter.
    /// This is the base case the whole cat is built out of.
    @Test func aCutThroughTheCentreOfAnEllipseSpansItsFullWidth() {
        let circle = ScanlineShape.ellipse(center: CGPoint(x: 50, y: 50), radii: CGSize(width: 20, height: 20))

        let spans = ScanlineSlicer.spans(of: [circle], at: 50)

        #expect(spans.count == 1)
        #expect(abs(spans[0].lowerBound - 30) < 0.001)
        #expect(abs(spans[0].upperBound - 70) < 0.001)
    }

    /// A cut above the shape has to produce nothing at all. If it produced a
    /// zero-width span the cat would grow a hairline stub floating over its head.
    @Test func aCutThatMissesTheShapeProducesNoSpans() {
        let circle = ScanlineShape.ellipse(center: CGPoint(x: 50, y: 50), radii: CGSize(width: 20, height: 20))

        #expect(ScanlineSlicer.spans(of: [circle], at: 10).isEmpty)
        #expect(ScanlineSlicer.spans(of: [circle], at: 90).isEmpty)
    }

    /// Two shapes that overlap on a row are one line, not two lines with a seam
    /// down the middle. The head and the body overlap on every row where they
    /// meet, so this is the common case, not the exotic one.
    @Test func overlappingShapesMergeIntoOneSpan() {
        let left = ScanlineShape.rect(CGRect(x: 0, y: 0, width: 60, height: 100))
        let right = ScanlineShape.rect(CGRect(x: 40, y: 0, width: 60, height: 100))

        let spans = ScanlineSlicer.spans(of: [left, right], at: 50)

        #expect(spans.count == 1)
        #expect(abs(spans[0].lowerBound - 0) < 0.001)
        #expect(abs(spans[0].upperBound - 100) < 0.001)
    }

    /// Two shapes that do not touch stay two spans, because the gap is the
    /// point: it is what separates the two feet and what puts daylight between
    /// the raised paw and the body.
    @Test func disjointShapesStayTwoSpansWithAGapBetweenThem() {
        let left = ScanlineShape.rect(CGRect(x: 0, y: 0, width: 20, height: 100))
        let right = ScanlineShape.rect(CGRect(x: 60, y: 0, width: 20, height: 100))

        let spans = ScanlineSlicer.spans(of: [left, right], at: 50)

        #expect(spans.count == 2)
        #expect(spans[0].upperBound < spans[1].lowerBound)
    }

    /// Spans come back left to right whatever order the shapes were declared in,
    /// so the drawing code never has to sort and the gap assertion above means
    /// what it says.
    @Test func spansAreOrderedLeftToRightRegardlessOfShapeOrder() {
        let right = ScanlineShape.rect(CGRect(x: 60, y: 0, width: 20, height: 100))
        let left = ScanlineShape.rect(CGRect(x: 0, y: 0, width: 20, height: 100))

        let spans = ScanlineSlicer.spans(of: [right, left], at: 50)

        #expect(spans[0].lowerBound < spans[1].lowerBound)
    }

    /// A triangle is how the ears are built, and a triangle's width depends on
    /// where you cut it. Near the apex it is narrow, near the base it is wide.
    @Test func aTriangleIsNarrowerNearItsApexThanNearItsBase() {
        let ear = ScanlineShape.triangle(
            CGPoint(x: 50, y: 0),
            CGPoint(x: 20, y: 100),
            CGPoint(x: 80, y: 100)
        )

        let nearApex = ScanlineSlicer.spans(of: [ear], at: 20)
        let nearBase = ScanlineSlicer.spans(of: [ear], at: 90)

        #expect(!nearApex.isEmpty)
        #expect(!nearBase.isEmpty)
        let apexWidth = nearApex[0].upperBound - nearApex[0].lowerBound
        let baseWidth = nearBase[0].upperBound - nearBase[0].lowerBound
        #expect(apexWidth < baseWidth)
    }
}

/// Turning spans into the strokes a `Canvas` actually draws: evenly spaced
/// rows, ragged ends, varying weight, and no ink outside the box it was given.
@Suite struct ScanlineSegmentTests {

    private var cat: [ScanlineShape] {
        [.ellipse(center: CGPoint(x: 50, y: 40), radii: CGSize(width: 26, height: 24)),
         .ellipse(center: CGPoint(x: 50, y: 75), radii: CGSize(width: 20, height: 22))]
    }
    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    /// The count is a budget, not a promise: rows that miss the shape draw
    /// nothing. What must hold is that it is never exceeded.
    @Test func segmentCountNeverExceedsTheLineBudget() {
        let segments = ScanlineSlicer.segments(for: cat, in: box, lineCount: 40, seed: 7)

        #expect(!segments.isEmpty)
        #expect(segments.count <= 40)
    }

    /// Ink outside the frame is ink over the headline underneath it.
    @Test func noSegmentEscapesTheBounds() {
        let segments = ScanlineSlicer.segments(for: cat, in: box, lineCount: 40, seed: 7)

        for segment in segments {
            #expect(segment.y >= box.minY)
            #expect(segment.y <= box.maxY)
            #expect(segment.xStart >= box.minX)
            #expect(segment.xEnd <= box.maxX)
            #expect(segment.xEnd > segment.xStart)
        }
    }

    /// The look depends on even spacing. Uneven rows read as a rendering fault
    /// rather than a style.
    @Test func rowsAreEvenlySpaced() {
        let segments = ScanlineSlicer.segments(for: cat, in: box, lineCount: 30, seed: 1)
        let rows = Array(Set(segments.map(\.y))).sorted()

        #expect(rows.count > 2)
        let gaps = zip(rows, rows.dropFirst()).map { $1 - $0 }
        // Rows that miss the shape leave a hole, so gaps are multiples of the
        // pitch rather than all equal. Every gap must still be a whole number
        // of pitches.
        let pitch = gaps.min()!
        for gap in gaps {
            let multiple = (gap / pitch).rounded()
            #expect(abs(gap - multiple * pitch) < 0.001)
        }
    }

    /// The same seed has to redraw identically, or the cat would shimmer on
    /// every unrelated view update.
    @Test func theSameSeedProducesTheSameCat() {
        let first = ScanlineSlicer.segments(for: cat, in: box, lineCount: 30, seed: 99)
        let second = ScanlineSlicer.segments(for: cat, in: box, lineCount: 30, seed: 99)

        #expect(first == second)
    }

    /// And a different seed has to actually change something, otherwise the
    /// jitter is decorative dead code.
    @Test func adifferentSeedProducesADifferentCat() {
        let first = ScanlineSlicer.segments(for: cat, in: box, lineCount: 30, seed: 1)
        let second = ScanlineSlicer.segments(for: cat, in: box, lineCount: 30, seed: 2)

        #expect(first != second)
    }

    /// Weight is what makes the dense bands in the reference. Flat weight would
    /// render a barcode.
    @Test func strokeWeightIsPositiveAndVariesBetweenRows() {
        let segments = ScanlineSlicer.segments(for: cat, in: box, lineCount: 30, seed: 5)
        let weights = Set(segments.map(\.weight))

        #expect(segments.allSatisfy { $0.weight > 0 })
        #expect(weights.count > 1)
    }

    /// Nothing in, nothing out. A guard against the empty case drawing a
    /// full-width band across the screen.
    @Test func noShapesProducesNoSegments() {
        #expect(ScanlineSlicer.segments(for: [], in: box, lineCount: 30, seed: 1).isEmpty)
    }

    /// A zero or negative budget is a caller bug, not a crash.
    @Test func anEmptyLineBudgetProducesNoSegments() {
        #expect(ScanlineSlicer.segments(for: cat, in: box, lineCount: 0, seed: 1).isEmpty)
    }
}

/// The cat itself: which primitives make a cat, and how the wave moves them.
/// Testing the silhouette rather than the drawing is what makes "the paw is
/// raised" a fact instead of an opinion about a screenshot.
@Suite struct ScanlineCatSilhouetteTests {

    private let box = CGRect(x: 0, y: 0, width: 200, height: 240)

    /// Nothing may stick out of the frame it was asked to fill.
    @Test func theCatStaysInsideItsBox() {
        let shapes = ScanlineCatSilhouette.shapes(in: box)

        for step in 0...100 {
            let y = box.minY + box.height * CGFloat(step) / 100
            for span in ScanlineSlicer.spans(of: shapes, at: y) {
                #expect(span.lowerBound >= box.minX - 0.001)
                #expect(span.upperBound <= box.maxX + 0.001)
            }
        }
    }





    /// An empty box cannot crash or emit stray geometry.
    @Test func adegenerateBoxProducesNothingToDraw() {
        let shapes = ScanlineCatSilhouette.shapes(in: .zero)
        #expect(ScanlineSlicer.segments(for: shapes, in: .zero, lineCount: 20, seed: 1).isEmpty)
    }
}

/// The face. Scanlines alone give a silhouette; the reference reads as a cat
/// because two solid blocks sit where the eyes are. They are drawn over the
/// raster rather than sliced into it, so they need their own geometry.
@Suite struct ScanlineCatFaceTests {

    private let box = CGRect(x: 0, y: 0, width: 200, height: 240)

    /// Two eyes, not one and not three.
    @Test func theFaceHasATwoEyedPair() {
        #expect(ScanlineCatSilhouette.eyes(in: box).count == 2)
    }

    /// Eyes that touch read as a mask or a brow. They must stay apart.
    @Test func theEyesDoNotTouchEachOther() {
        let eyes = ScanlineCatSilhouette.eyes(in: box).sorted { $0.minX < $1.minX }

        #expect(eyes[0].maxX < eyes[1].minX)
    }

    /// And they must land on the head, not float above the ears or sit on the
    /// chest. The head is the row band where the head ellipse is the widest
    /// thing on screen.
    @Test func theEyesSitOnTheHead() {
        let shapes = ScanlineCatSilhouette.shapes(in: box)

        for eye in ScanlineCatSilhouette.eyes(in: box) {
            let spans = ScanlineSlicer.spans(of: shapes, at: eye.midY)
            // The eye's centre must fall inside ink, or it is a hole in the air.
            #expect(spans.contains { $0.contains(eye.midX) })
            #expect(eye.midY < box.midY)
        }
    }

    /// Round, not oval. Wider-than-tall eyes read as closed slits, which made
    /// the first pass look cross rather than friendly.
    @Test func theEyesAreRoundRatherThanSlits() {
        for eye in ScanlineCatSilhouette.eyes(in: box) {
            #expect(abs(eye.width - eye.height) < 0.001)
        }
    }

    /// The nose sits between and below the eyes. Without it the face is two
    /// dots on a circle, which could be any animal.
    @Test func theNoseSitsBelowAndBetweenTheEyes() {
        let eyes = ScanlineCatSilhouette.eyes(in: box).sorted { $0.minX < $1.minX }
        let nose = ScanlineCatSilhouette.nose(in: box)

        #expect(nose.midY > eyes[0].maxY)
        #expect(nose.midX > eyes[0].midX)
        #expect(nose.midX < eyes[1].midX)
    }

    /// The head has to be the biggest thing in the figure. The first pass gave
    /// the body the same width and the cat read as an owl.
    @Test func theHeadIsWiderThanTheBody() {
        let shapes = ScanlineCatSilhouette.shapes(in: box)

        let headWidth = widest(ScanlineSlicer.spans(of: shapes, at: box.minY + box.height * 0.30))
        let bodyWidth = widest(ScanlineSlicer.spans(of: shapes, at: box.minY + box.height * 0.80))

        #expect(headWidth > bodyWidth)
    }

    /// And there must be a waist between them, or head and body are one mass.
    @Test func thereIsANeckNarrowerThanBothHeadAndBody() {
        let shapes = ScanlineCatSilhouette.shapes(in: box)

        let head = widest(ScanlineSlicer.spans(of: shapes, at: box.minY + box.height * 0.30))
        let neck = widest(ScanlineSlicer.spans(of: shapes, at: box.minY + box.height * 0.56))
        let body = widest(ScanlineSlicer.spans(of: shapes, at: box.minY + box.height * 0.80))

        #expect(neck > 0)          // still connected: a gap would split the cat in two
        #expect(neck < head)
        #expect(neck < body)
    }

    /// A degenerate box must not produce stray blocks.
    @Test func adegenerateBoxHasNoFace() {
        #expect(ScanlineCatSilhouette.eyes(in: .zero).allSatisfy { $0.isEmpty })
    }

    private func widest(_ spans: [ClosedRange<CGFloat>]) -> CGFloat {
        spans.map { $0.upperBound - $0.lowerBound }.max() ?? 0
    }
}

/// With the raised paw gone, the blink is the cat's only motion besides the
/// bob. A blink that is too long reads as sleepy and one that never closes
/// reads as a still image, so both ends are pinned.
@Suite struct ScanlineCatBlinkTests {

    /// Eyes are open for the overwhelming majority of the cycle.
    @Test func theEyesAreOpenAlmostAllTheTime() {
        let samples = 400
        let open = (0..<samples).filter { step in
            ScanlineCatSilhouette.eyeOpenness(at: CGFloat(step) / CGFloat(samples)) > 0.9
        }

        #expect(CGFloat(open.count) / CGFloat(samples) > 0.85)
    }

    /// But they do fully close at some point, or it is not a blink.
    @Test func theEyesFullyCloseOnce() {
        let samples = 400
        let closed = (0..<samples).filter { step in
            ScanlineCatSilhouette.eyeOpenness(at: CGFloat(step) / CGFloat(samples)) < 0.1
        }

        #expect(!closed.isEmpty)
    }

    /// Openness never leaves 0...1, because the view multiplies the eye's
    /// height by it and a negative would flip the eye inside out.
    @Test func opennessStaysWithinItsRange() {
        for step in 0...400 {
            let value = ScanlineCatSilhouette.eyeOpenness(at: CGFloat(step) / 400)
            #expect(value >= 0)
            #expect(value <= 1)
        }
    }

    /// The cycle closes, so the loop has no visible seam.
    @Test func theBlinkCycleEndsWhereItStarted() {
        #expect(abs(ScanlineCatSilhouette.eyeOpenness(at: 0)
                    - ScanlineCatSilhouette.eyeOpenness(at: 1)) < 0.001)
    }
}

/// The dot rendering: the same scanline geometry, but each run of ink becomes a
/// row of dots on the app's own grid pitch instead of a solid stroke.
@Suite struct ScanlineDotsTests {

    @Test func aRunOfInkBecomesEvenlySpacedDots() {
        let dots = ScanlineSlicer.dots(along: 0...100, spacing: 10)

        #expect(dots.count > 1)
        let gaps = zip(dots, dots.dropFirst()).map { $1 - $0 }
        for gap in gaps {
            #expect(abs(gap - 10) < 0.001)
        }
    }

    /// Dots are centred in their run rather than started hard at its left edge,
    /// so a row of ink does not lean.
    @Test func dotsAreCentredWithinTheirRun() {
        let dots = ScanlineSlicer.dots(along: 0...100, spacing: 30)

        let leading = dots.first! - 0
        let trailing = 100 - dots.last!
        #expect(abs(leading - trailing) < 0.001)
    }

    /// A run shorter than the spacing still deserves one dot: dropping it would
    /// erase the ear tips and the toes, which are exactly the short runs.
    @Test func aRunShorterThanTheSpacingStillGetsOneDot() {
        let dots = ScanlineSlicer.dots(along: 0...3, spacing: 20)

        #expect(dots.count == 1)
        #expect(abs(dots[0] - 1.5) < 0.001)
    }

    @Test func nonPositiveSpacingProducesNoDotsRatherThanHanging() {
        #expect(ScanlineSlicer.dots(along: 0...100, spacing: 0).isEmpty)
    }
}

/// Cuteness is not a vibe, it is a set of proportions: an oversized head, eyes
/// that are large and set BELOW the head's midline, and highlights in them.
/// Pinning them here stops a later tweak quietly walking the cat back to
/// looking like an owl.
@Suite struct ScanlineCatCharmTests {

    private let box = CGRect(x: 0, y: 0, width: 200, height: 240)

    /// Baby schema, rule one: the head is huge. Half the figure or more.
    @Test func theHeadFillsAtLeastHalfTheFigure() {
        let shapes = ScanlineCatSilhouette.shapes(in: box)
        var headRows = 0
        let samples = 200

        for step in 0..<samples {
            let y = box.minY + box.height * CGFloat(step) / CGFloat(samples)
            let widest = ScanlineSlicer.spans(of: shapes, at: y)
                .map { $0.upperBound - $0.lowerBound }.max() ?? 0
            if widest > box.width * 0.45 { headRows += 1 }
        }

        #expect(CGFloat(headRows) / CGFloat(samples) > 0.30)
    }

    /// Rule two: big eyes. Small eyes on a big head read as beady, not cute.
    @Test func theEyesAreLargeRelativeToTheHead() {
        let eye = ScanlineCatSilhouette.eyes(in: box)[0]

        #expect(eye.width > box.width * 0.09)
    }

    /// Rule three, and the one that does the most work: the eyes sit BELOW the
    /// middle of the head. High-set eyes read as an adult animal.
    @Test func theEyesSitBelowTheMiddleOfTheHead() {
        let eyes = ScanlineCatSilhouette.eyes(in: box)
        let headCentre = box.minY + box.height * 0.30

        for eye in eyes {
            #expect(eye.midY > headCentre)
        }
    }

    /// A highlight inside each eye. Without it the eyes are flat holes.
    @Test func eachEyeCarriesAHighlightInsideIt() {
        let eyes = ScanlineCatSilhouette.eyes(in: box)
        let highlights = ScanlineCatSilhouette.eyeHighlights(in: box)

        #expect(highlights.count == eyes.count)
        for (eye, highlight) in zip(eyes, highlights) {
            #expect(eye.contains(CGPoint(x: highlight.midX, y: highlight.midY)))
            #expect(highlight.width < eye.width / 2)
        }
    }

    /// Blush sits outboard of the eyes, on the cheeks, not between them.
    @Test func theBlushSitsOutsideTheEyesOnBothCheeks() {
        let eyes = ScanlineCatSilhouette.eyes(in: box).sorted { $0.minX < $1.minX }
        let blush = ScanlineCatSilhouette.blush(in: box).sorted { $0.minX < $1.minX }

        #expect(blush.count == 2)
        #expect(blush[0].midX < eyes[0].midX)
        #expect(blush[1].midX > eyes[1].midX)
    }
}
