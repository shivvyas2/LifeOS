import Foundation
import CoreGraphics

/// Where the rings sit over YouTube's player.
///
/// Section 5.3: the top leading edge in either orientation, the region
/// farthest from the control bar and the branding that YouTube's terms name.
/// `landscapeOverlay` off falls back to the portrait stack in landscape too.
enum VideoWorkoutLayout {
    static let landscapeOverlay = true
    /// Inset from the safe area's top leading corner, in points.
    static let overlayInset: CGFloat = 16
    /// The Start pill's height in landscape.
    static let overlayMaxHeight: CGFloat = 44
    /// The player's aspect ratio in portrait.
    static let playerAspectRatio: CGFloat = 16.0 / 9.0
    /// The band along the bottom of the player where YouTube draws its
    /// control bar and its logo. The rings can be dragged anywhere else; a
    /// drop here is moved off it, so the terms the top leading default was
    /// chosen for still hold wherever the rings end up.
    static let controlStripHeight: CGFloat = 56

    /// The strip for a player that fills `container`, or one whose frame
    /// inside it is known.
    static func controlStrip(in container: CGSize, player: CGRect? = nil) -> CGRect {
        let frame = player ?? CGRect(origin: .zero, size: container)
        return CGRect(x: frame.minX, y: frame.maxY - controlStripHeight,
                      width: frame.width, height: controlStripHeight)
    }

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
        // `fs=0` removes YouTube's own full screen button. That button hands
        // the video to a system layer above the whole app, where no HUD can
        // be drawn; the screen offers its own full screen instead, with the
        // rings still over the picture.
        return URL(string: "https://www.youtube-nocookie.com/embed/\(youtubeID)"
            + "?origin=\(embedOrigin)&enablejsapi=1&playsinline=1&rel=0&modestbranding=1&fs=0")
    }
}
