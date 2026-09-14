import SwiftUI
import WebKit

/// YouTube's own player, on the privacy-enhanced domain, playing inline.
///
/// There is no JavaScript bridge here on purpose: the person taps YouTube's
/// play button, which is the one gesture the embed needs, and the recorder
/// times the session rather than trying to follow the video's clock. When the
/// page itself cannot load, `onLoadFailure` raises the "Open in YouTube"
/// fallback. A video the owner has barred from embedding loads a page that
/// says so inside the player, which no delegate call can see without the
/// JavaScript bridge this slice leaves out; YouTube's own card carries a
/// "Watch video on YouTube" button in that case.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    var onLoadFailure: () -> Void = {}

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.navigationDelegate = context.coordinator
        context.coordinator.load(videoID, into: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onLoadFailure = onLoadFailure
        // Only a different video reloads. A re-render during a session must
        // not restart what the person is already following.
        context.coordinator.load(videoID, into: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLoadFailure: onLoadFailure) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onLoadFailure: () -> Void
        private var loaded: String?

        init(onLoadFailure: @escaping () -> Void) { self.onLoadFailure = onLoadFailure }

        func load(_ videoID: String, into view: WKWebView) {
            guard loaded != videoID, let url = VideoWorkoutLayout.embedURL(youtubeID: videoID) else { return }
            loaded = videoID
            // Loading the embed URL straight into the web view answers with
            // "Video player configuration error, Error 153": the embed wants
            // an embedding page it can read a referrer from. So the iframe is
            // wrapped in a page of our own, based at youtube.com, which is
            // what the player asks for and what every embed on the web is.
            view.loadSimulatedRequest(URLRequest(url: Self.base), responseHTML: Self.page(embedding: url))
        }

        static let base = URL(string: "https://www.youtube.com/")!

        static func page(embedding url: URL) -> String {
            """
            <!DOCTYPE html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <style>*{margin:0;padding:0}html,body{background:#000;height:100%;overflow:hidden}
            iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
            </head><body><iframe src="\(url.absoluteString)" allow="autoplay; encrypted-media; picture-in-picture"
            allowfullscreen></iframe></body></html>
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
