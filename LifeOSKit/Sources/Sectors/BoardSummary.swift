import Foundation
import Persistence

/// The two facts the board header carries.
///
/// There is deliberately no combined life score. An average of nine sectors
/// sits near the middle forever and moves by fractions, which reads as nothing
/// happening in a month where one sector collapsed and another soared. Worse,
/// it invites protecting the average instead of attending to the weak sector.
public struct BoardSummary: Sendable, Equatable {
    private let scores: [LifeSector: Int]
    private let previous: [LifeSector: Int]

    public init(scores: [LifeSector: Int], previous: [LifeSector: Int]) {
        self.scores = scores
        self.previous = previous
    }

    /// The sector most worth attention.
    ///
    /// Walks board order and `min(by:)` keeps the first of equal elements, so
    /// a tie breaks by board order rather than by dictionary iteration, which
    /// would make the header flicker between two equally low sectors.
    public var lowest: LifeSector? {
        LifeSector.boardOrder
            .compactMap { sector in scores[sector].map { (sector, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// The largest change since last month, counting only sectors scored in
    /// both. A tie goes to the drop, which is the more useful thing to say.
    public var biggestMover: (sector: LifeSector, delta: Int)? {
        let moves: [(LifeSector, Int)] = LifeSector.boardOrder.compactMap { sector in
            guard let now = scores[sector], let then = previous[sector] else { return nil }
            let delta = now - then
            return delta == 0 ? nil : (sector, delta)
        }
        guard let best = moves.max(by: { lhs, rhs in
            abs(lhs.1) < abs(rhs.1) || (abs(lhs.1) == abs(rhs.1) && lhs.1 > rhs.1)
        }) else { return nil }
        return (best.0, best.1)
    }
}
