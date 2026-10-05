import Foundation

/// Notices the end of a rally from the swings alone: at least one swing, then
/// a stretch with none. It cannot say who won; nothing on the wrist can. What
/// it can do is ask at the one moment the answer is easy to give, so scoring
/// is a single tap during the natural pause instead of a remembered chore.
public struct RallyEndDetector: Sendable {
    /// Quiet after the last swing before a rally counts as over. Long enough
    /// that a lift, a clear and the reply are one rally; short enough to ask
    /// while the players are still walking back.
    public var quietAfter: TimeInterval
    private var lastSwingAt: Double?
    private var asked = false

    public init(quietAfter: TimeInterval = 4) { self.quietAfter = quietAfter }

    /// A swing was detected at this active time.
    public mutating func swing(at time: Double) {
        lastSwingAt = time
        asked = false
    }

    /// The point was scored, by the prompt or otherwise: the rally is closed.
    public mutating func scored() {
        lastSwingAt = nil
        asked = false
    }

    /// Pauses and gaps never turn into a prompt.
    public mutating func interrupt() { scored() }

    /// True exactly once per rally, when it has gone quiet long enough.
    public mutating func shouldAsk(at time: Double) -> Bool {
        guard let lastSwingAt, !asked, time - lastSwingAt >= quietAfter else { return false }
        asked = true
        return true
    }
}
