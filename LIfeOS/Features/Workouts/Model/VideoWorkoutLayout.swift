import Foundation

/// Where the HUD sits over YouTube's player.
///
/// Section 5.3: in landscape the collapsed capsule floats at the top leading
/// edge, the region farthest from the control bar and the branding that
/// YouTube's terms name. The side rail is kept as a code path behind
/// `landscapeOverlay` so that, if the overlay is ever flagged, the fallback is
/// a flag flip rather than a redesign.
enum VideoWorkoutLayout {
    static let landscapeOverlay = true
    /// Inset from the safe area's top leading corner, in points.
    static let overlayInset: CGFloat = 16
    /// The capsule never grows past this, and never expands in landscape.
    static let overlayMaxHeight: CGFloat = 44
    /// The player's aspect ratio in portrait.
    static let playerAspectRatio: CGFloat = 16.0 / 9.0

    static func embedURL(youtubeID: String) -> URL? {
        URL(string: "https://www.youtube-nocookie.com/embed/\(youtubeID)?playsinline=1&rel=0&modestbranding=1")
    }
}
