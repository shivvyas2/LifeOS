import UIKit

/// Turns a picked photo into a JPEG the `avatars` bucket will accept.
///
/// Shared by signup and the profile edit sheet, the two places a photo is
/// picked. They held identical copies of the box, the render scale and the
/// encoding, which is three things that had to be changed in two places or
/// quietly drift apart.
enum ProfilePhotoDownsizing {
    /// The longest side, in points, a stored avatar is kept at.
    static let side: CGFloat = 512

    /// Matches `file_size_limit` on the `avatars` bucket in
    /// `20260828140000_profiles_and_avatars.sql`. The client cannot ask
    /// Storage what a bucket allows, so this is kept in step by hand.
    ///
    /// Deliberately the bucket's real ceiling rather than something tighter.
    /// `20260828150000_avatars_signed_in_only.sql` records why the limit was
    /// left where it is: tightening it starts rejecting uploads from installs
    /// still running older code, with nothing on screen to explain it. A
    /// client-side constant below the server's would reintroduce exactly that
    /// failure, one release earlier.
    static let sizeLimit = 5_242_880

    /// A 512 point box, rendered at scale 1, encoded as JPEG under the
    /// bucket's ceiling. Nil when the image cannot be encoded at all.
    ///
    /// Scale 1 because the renderer otherwise draws at the device's scale, so
    /// a 512 point box becomes a 1536 pixel bitmap on a 3x phone: nine times
    /// the pixels asked for, which undoes most of the downsizing.
    static func jpeg(from image: UIImage) -> Data? {
        let ratio = min(side / image.size.width, side / image.size.height, 1)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        // Quality 0.8 first, stepping down only for a photo dense enough to
        // still sit near the ceiling at that quality. A backstop against a
        // pathological image, not the primary way the output is kept small:
        // rendering at scale 1 is what does that, and at 512 points a normal
        // photo lands far under the limit on the first pass.
        var quality: CGFloat = 0.8
        var data = resized.jpegData(compressionQuality: quality)
        while let current = data, current.count > sizeLimit, quality > 0.3 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }
}
