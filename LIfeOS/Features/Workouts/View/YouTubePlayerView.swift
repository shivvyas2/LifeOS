import SwiftUI
import WebKit

/// The web view behind the player, owned by the screen rather than the view.
///
/// Portrait, full screen and landscape are different layouts of the same
/// player, and SwiftUI gives a view in a different branch a different
/// identity, which would mean a new web view and a video starting over every
/// time the phone turned or the full screen button was tapped. Holding the
/// web view here, in the screen's state, lets each layout show the one that
/// is already playing.
@MainActor
final class YouTubePlayerHost {
    let webView: WKWebView
    /// The video the page currently embeds, so a re-render never reloads it.
    fileprivate var loaded: String?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
    }
}

/// YouTube's own player, on the privacy-enhanced domain, playing inline.
///
/// There is no JavaScript bridge here on purpose: the person taps YouTube's
/// play button, which is the one gesture the embed needs, and the recorder
/// times the session rather than trying to follow the video's clock. When the
/// page itself cannot load, or the row's id is not a YouTube id at all,
/// `onLoadFailure` raises the "Open in YouTube" fallback. A video the owner has barred from embedding loads a page that
/// says so inside the player, which no delegate call can see without the
/// JavaScript bridge this slice leaves out; YouTube's own card carries a
/// "Watch video on YouTube" button in that case.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let host: YouTubePlayerHost
    var onLoadFailure: () -> Void = {}

    func makeUIView(context: Context) -> WKWebView {
        let view = host.webView
        // Moving between layouts: the view may still sit in the last
        // layout's container for a frame.
        view.removeFromSuperview()
        view.navigationDelegate = context.coordinator
        context.coordinator.load(videoID, into: view, host: host)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onLoadFailure = onLoadFailure
        // Only a different video reloads. A re-render during a session must
        // not restart what the person is already following.
        context.coordinator.load(videoID, into: view, host: host)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLoadFailure: onLoadFailure) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLoadFailure: () -> Void

        init(onLoadFailure: @escaping () -> Void) { self.onLoadFailure = onLoadFailure }

        @MainActor
        func load(_ videoID: String, into view: WKWebView, host: YouTubePlayerHost) {
            guard host.loaded != videoID else { return }
            guard let url = VideoWorkoutLayout.embedURL(youtubeID: videoID) else {
                // Not a YouTube id, so nothing is interpolated anywhere. Said
                // out loud on the next turn of the run loop, because this runs
                // inside `makeUIView` and a state change during a body pass is
                // a change SwiftUI has already started rendering past.
                host.loaded = videoID
                let report = onLoadFailure
                DispatchQueue.main.async { report() }
                return
            }
            host.loaded = videoID
            // Loading the embed URL straight into the web view answers with
            // "Video player configuration error, Error 153": the embed needs a
            // page with an origin to sit in. So the iframe is wrapped in a
            // page of our own, based at the host the embed's `origin` names,
            // which is what youtube-ios-player-helper does too.
            view.loadHTMLString(Self.page(embedding: url), baseURL: Self.base)
        }

        static let base = URL(string: VideoWorkoutLayout.embedOrigin)

        static func page(embedding url: URL) -> String {
            """
            <!DOCTYPE html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <style>*{margin:0;padding:0}html,body{background:#000;height:100%;overflow:hidden}
            iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
            </head><body><iframe src="\(url.absoluteString)" allow="autoplay; encrypted-media; picture-in-picture"></iframe></body></html>
            """
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadFailure()
        }
    }
}
