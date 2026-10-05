import Foundation
import Persistence

/// Decides which month the board should offer to close, if any.
///
/// Kept pure and separate from `SectorStore` because of a deadlock in the
/// naive version: a query over `SectorScore` rows only sees months that
/// already have at least one row, and rows are created only by `record()`,
/// which runs only during a close. On a fresh install there are no rows at
/// all, so the query returns nothing, the board shows no banner, the close
/// can never start, and no rows are ever created. This type breaks that cycle
/// by falling back to the previous month whenever the store has nothing to
/// report yet.
public enum CloseSchedule {
    /// The newest month with any sector scored, or nil when nothing was ever
    /// closed. A month skipped since then does not erase the ones before it.
    public static func lastClosedMonth(scoredCounts: [Date: Int]) -> Date? {
        scoredCounts.filter { $0.value > 0 }.keys.max()
    }

    /// Which month the board should offer to close, if any.
    ///
    /// `scoredCounts` is every month that has at least one `SectorScore` row,
    /// each mapped to how many of its sectors are actually scored
    /// (`SectorStore.scoredCounts(before:)`). Within a bounded look-back
    /// ending at `previousMonth`, the OLDEST month with fewer than
    /// `totalSectors` scored is offered, so a gap two months back surfaces
    /// before a more recent one and is never buried under a newer month.
    ///
    /// A month outside the look-back is never offered even if it has a gap:
    /// unbounded, one truly ancient partial month would pin the banner
    /// forever. `scoredSectorsInPreviousMonth` is the fallback for a fresh
    /// install, where `scoredCounts` is empty because no close has ever run
    /// and there is nothing in it to scan.
    public static func monthAwaitingClose(
        scoredCounts: [Date: Int],
        previousMonth: Date,
        scoredSectorsInPreviousMonth: Int,
        totalSectors: Int = LifeSector.boardOrder.count,
        lookbackMonths: Int = 12,
        calendar: Calendar = .current
    ) -> Date? {
        let earliestAllowed = calendar.date(
            byAdding: .month, value: -(lookbackMonths - 1), to: previousMonth
        ) ?? previousMonth

        let oldestGap = scoredCounts
            .filter { month, scored in
                scored < totalSectors && month >= earliestAllowed && month <= previousMonth
            }
            .keys
            .min()

        if let oldestGap { return oldestGap }
        return scoredSectorsInPreviousMonth < totalSectors ? previousMonth : nil
    }
}
