import SwiftUI
import Observation

/// Where each anchor is on screen right now, in the global coordinate space.
/// A view that is not on screen has no frame.
@MainActor @Observable
public final class WalkthroughFrames {
    public private(set) var frames: [WalkthroughAnchor: CGRect] = [:]

    public init() {}

    public var available: Set<WalkthroughAnchor> { Set(frames.keys) }

    public func report(_ anchor: WalkthroughAnchor, _ frame: CGRect?) {
        if let frame, !frame.isEmpty { frames[anchor] = frame } else { frames[anchor] = nil }
    }
}

public extension EnvironmentValues {
    /// Nil outside a walkthrough's host, which makes every anchor a no-op.
    @Entry var walkthroughFrames: WalkthroughFrames? = nil
}

private struct WalkthroughAnchorModifier: ViewModifier {
    let anchor: WalkthroughAnchor?
    @Environment(\.walkthroughFrames) private var frames
    /// A view coming back from under a pushed screen reappears where it was,
    /// so its geometry does not change and would never report again.
    @State private var lastFrame: CGRect?

    func body(content: Content) -> some View {
        if let anchor, let frames {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    lastFrame = frame
                    frames.report(anchor, frame)
                }
                .onAppear { if let lastFrame { frames.report(anchor, lastFrame) } }
                .onDisappear { frames.report(anchor, nil) }
        } else {
            content
        }
    }
}

public extension View {
    /// Reports this view's frame for the walkthrough step that points at it.
    func walkthroughAnchor(_ anchor: WalkthroughAnchor?) -> some View {
        modifier(WalkthroughAnchorModifier(anchor: anchor))
    }
}
