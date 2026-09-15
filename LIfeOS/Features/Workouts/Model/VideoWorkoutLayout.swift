import Foundation

/// Where the HUD sits over YouTube's player.
///
/// Section 5.3: in landscape the collapsed capsule floats at the top leading
/// edge, the region farthest from the control bar and the branding that
/// YouTube's terms name. `landscapeOverlay` off falls back to the portrait
/// stack, which is the layout this app actually renders and verifies today.
/// The side rail the spec sketched is not kept as a second code path: an
/// off-branch that has never rendered is not a retreat path, and it is in
/// git history if rotation is ever enabled.
enum VideoWorkoutLayout {
    static let landscapeOverlay = true
    /// Inset from the safe area's top leading corner, in points.
    static let overlayInset: CGFloat = 16
    /// The capsule never grows past this, and never expands in landscape.
    static let overlayMaxHeight: CGFloat = 44
    /// The player's aspect ratio in portrait.
    static let playerAspectRatio: CGFloat = 16.0 / 9.0

    /// `origin` and `enablejsapi` are what the embed checks before it will
    /// play: with no origin at all it answers "Video player configuration
    /// error", and with `youtube.com` as the origin, "This video is
    /// unavailable". The privacy-enhanced host is the one it accepts, and it
    /// is also the host `YouTubePlayerView` bases its wrapper page at, so the
    /// page and the iframe agree about where this embed is.
    static let embedOrigin = "https://www.youtube-nocookie.com"

    /// YouTube ids are exactly eleven characters of an unreserved alphabet.
    /// Rows come from a service-role-written table, so a stray quote is not
    /// expected; checking anyway means nothing but an id is ever interpolated
    /// into the URL or the wrapper page's HTML, and the player says plainly
    /// that it cannot play a row that fails.
    static let idPattern = /^[A-Za-z0-9_-]{11}$/

    static func embedURL(youtubeID: String) -> URL? {
        guard youtubeID.wholeMatch(of: idPattern) != nil else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(youtubeID)"
            + "?origin=\(embedOrigin)&enablejsapi=1&playsinline=1&rel=0&modestbranding=1")
    }
}
