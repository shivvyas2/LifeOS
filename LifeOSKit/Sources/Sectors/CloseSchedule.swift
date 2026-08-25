import Foundation
import Persistence

/// Decides which month the board should offer to close, if any.
///
/// Kept pure and separate from `SectorStore` because of a deadlock in the
/// naive version: `SectorStore.oldestUnclosedMonth(before:)` only sees months
/// that already have at least one `SectorScore` row, and rows are created only
/// by `record()`, which runs only during a close. On a fresh install there are
/// no rows at all, so the query returns nil, the board shows no banner, the
/// close can never start, and no rows are ever created. This type breaks that
/// cycle by falling back to the previous month whenever the store has nothing
/// to report yet.
public enum CloseSchedule {
    /// Which month the board should offer to close, if any.
    ///
    /// Falls back to the previous month when no score rows exist yet, because
    /// rows are only created by a close, so waiting for one would deadlock a
    /// fresh install into never being able to start.
    public static func monthAwaitingClose(
        oldestUnclosed: Date?,
        previousMonth: Date,
        scoredSectorsInPreviousMonth: Int,
        totalSectors: Int = LifeSector.boardOrder.count
    ) -> Date? {
        if let oldestUnclosed { return oldestUnclosed }
        return scoredSectorsInPreviousMonth < totalSectors ? previousMonth : nil
    }
}
