import CoreGraphics

/// The cat, as geometry rather than as art.
///
/// Everything is declared in a unit box and scaled to the frame it is given, so
/// the cat is resolution-independent and the numbers below read as proportions
/// instead of pixels. Keeping it separate from the view means "the head is
/// bigger than the body" and "there is a neck" are assertions a test can make,
/// not judgements about a screenshot.
///
/// Proportions follow the beckoning cat the design came from: a large head, a
/// small seated body, and one paw held up beside the head. An earlier pass gave
/// head and body the same width and the result read as an owl.
public enum ScanlineCatSilhouette {

    /// Every primitive that makes up the cat.
    ///
    /// No longer takes a wave: the raised paw is gone, and with it the only
    /// part of the body that moved. What is left animates in the view — a bob
    /// and a blink — rather than by rebuilding the silhouette every frame.
    public static func shapes(in rect: CGRect) -> [ScanlineShape] {
        [
            // Ears: tall, set wide, rooted inside the head so they read as ears
            // rather than horns. An ear only registers on the rows where it is
            // the only ink, which is why the apexes reach the top edge.
            // Shorter and set wider than the first pass. Tall spiky ears read
            // as a fox; a cute cat's ears are stubby triangles that barely
            // clear the skull.
            .triangle(point(rect, 0.20, 0.02), point(rect, 0.14, 0.22), point(rect, 0.38, 0.14)),
            .triangle(point(rect, 0.68, 0.02), point(rect, 0.50, 0.14), point(rect, 0.74, 0.22)),

            // The head, and now more than half the figure. Baby schema: the
            // single biggest lever on whether this reads as cute or as an
            // adult animal.
            .ellipse(center: point(rect, 0.44, 0.33), radii: size(rect, 0.30, 0.27)),

            // The neck: a bridge rather than a shape in its own right. Without
            // it the head's bottom and the body's top leave a gap and the cat
            // renders as two separate blobs.
            .rect(CGRect(
                x: rect.minX + rect.width * 0.34,
                y: rect.minY + rect.height * 0.56,
                width: rect.width * 0.20,
                height: rect.height * 0.10
            )),

            // The body: small, round and low. Chubby rather than long, which is
            // the other half of the baby schema.
            .ellipse(center: point(rect, 0.44, 0.82), radii: size(rect, 0.185, 0.165)),

            // Tail: narrow, long, detached. The gap is what reads as a tail
            // rather than as a lumpy hip.
            .ellipse(center: point(rect, 0.17, 0.86), radii: size(rect, 0.038, 0.105)),

            // Feet, widening the base so the cat sits rather than floats.
            .ellipse(center: point(rect, 0.35, 0.965), radii: size(rect, 0.075, 0.035)),
            .ellipse(center: point(rect, 0.55, 0.965), radii: size(rect, 0.075, 0.035)),
        ]
    }

    /// How open the eyes are at this point in the cycle, 0 closed to 1 open.
    ///
    /// The cat used to wave; without the paw it needed something else alive in
    /// it, and a blink costs one multiply on the eye's height. Open for most of
    /// the cycle with one quick close, because a slow blink reads as sleepy and
    /// a frequent one as nervous.
    public static func eyeOpenness(at phase: CGFloat) -> CGFloat {
        let cycle = phase - phase.rounded(.down)
        // The blink occupies a narrow window; everything outside it is open.
        let window: CGFloat = 0.12
        guard cycle < window else { return 1 }
        // One smooth down-and-up across the window: 1 at both edges, 0 in the
        // middle, so the loop closes without a jump.
        let travel = cycle / window
        return (1 - cos(travel * 2 * .pi)) / 2
    }

    /// The two solid eye blocks, left then right.
    ///
    /// Drawn over the raster rather than sliced into it. Sliced, they would be
    /// more ink among ink and vanish: what makes an eye read is that it is SOLID
    /// where everything around it is striped.
    ///
    /// Square, so the view can round them into circles. The first pass made them
    /// wider than tall and the cat looked like it was squinting.
    public static func eyes(in rect: CGRect) -> [CGRect] {
        let diameter = min(rect.width, rect.height) * 0.115
        // Below the head's centre, which is the single change that turns a
        // watchful animal into a young one.
        let y = rect.minY + rect.height * 0.375
        return [0.315, 0.565].map { x in
            CGRect(
                x: rect.minX + rect.width * x - diameter / 2,
                y: y - diameter / 2,
                width: diameter,
                height: diameter
            )
        }
    }

    /// The catchlight in each eye, up and to the left.
    ///
    /// Small, and it does more for the face than anything else here: without it
    /// the eyes are two holes punched in the head.
    public static func eyeHighlights(in rect: CGRect) -> [CGRect] {
        eyes(in: rect).map { eye in
            let diameter = eye.width * 0.34
            return CGRect(
                x: eye.minX + eye.width * 0.20,
                y: eye.minY + eye.height * 0.18,
                width: diameter,
                height: diameter
            )
        }
    }

    /// Two soft cheek patches, outboard of the eyes.
    ///
    /// Drawn in the app's accent rather than in ink, so the one warm colour on
    /// the screen is the same orange that means "today" everywhere else.
    public static func blush(in rect: CGRect) -> [CGRect] {
        let width = min(rect.width, rect.height) * 0.105
        let height = width * 0.62
        let y = rect.minY + rect.height * 0.455
        return [0.235, 0.645].map { x in
            CGRect(
                x: rect.minX + rect.width * x - width / 2,
                y: y - height / 2,
                width: width,
                height: height
            )
        }
    }

    /// The mouth: a small shallow curve under the nose, as two points the view
    /// draws a quadratic through. A full smile is too much face for this size;
    /// a suggestion of one is enough.
    public static func mouth(in rect: CGRect) -> (start: CGPoint, control: CGPoint, end: CGPoint) {
        (
            start: point(rect, 0.395, 0.475),
            control: point(rect, 0.440, 0.510),
            end: point(rect, 0.485, 0.475)
        )
    }

    /// The nose: small, between and below the eyes. Without it the face is two
    /// dots on a circle and could belong to any animal.
    public static func nose(in rect: CGRect) -> CGRect {
        let width = min(rect.width, rect.height) * 0.055
        let height = width * 0.7
        return CGRect(
            x: rect.minX + rect.width * 0.44 - width / 2,
            y: rect.minY + rect.height * 0.448 - height / 2,
            width: width,
            height: height
        )
    }

    private static func point(_ rect: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    private static func size(_ rect: CGRect, _ width: CGFloat, _ height: CGFloat) -> CGSize {
        CGSize(width: rect.width * width, height: rect.height * height)
    }
}
