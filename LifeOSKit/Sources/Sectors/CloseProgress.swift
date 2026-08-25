import Foundation
import Persistence

/// Where a close has got to.
///
/// Membership of `scored` means the person actually decided, which is why a
/// skipped sector is offered again on the next visit: a score nobody looked at
/// is noise in the history. The caller decides what counts as "decided" for
/// its purposes: `MonthlyCloseViewModel` unions the sectors committed to the
/// store with the sectors skipped in the current session, so a skip moves the
/// close forward without ever writing a score for the sector skipped.
public struct CloseProgress: Sendable, Equatable {
    private let scored: Set<LifeSector>

    public init(scored: Set<LifeSector>) {
        self.scored = scored
    }

    public var next: LifeSector? {
        LifeSector.boardOrder.first { !scored.contains($0) }
    }

    public var position: Int { scored.count + 1 }
    public var total: Int { LifeSector.boardOrder.count }
    public var isComplete: Bool { next == nil }
}
