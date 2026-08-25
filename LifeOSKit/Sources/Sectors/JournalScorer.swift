import Foundation
import Persistence

/// Mind and Soul, from journal entries.
///
/// One rule for two sectors because they share their only data source today.
/// This is the thinnest evidence in the system and it is meant to be: when
/// sub-project two gives the two sectors distinct inputs, this type splits.
public struct JournalScorer: SectorScorer {
    public let sector: LifeSector

    private let entryDates: [Date]
    private let daysInMonth: Int
    private let previousEntryCount: Int?
    private let calendar: Calendar

    public init(
        sector: LifeSector,
        entryDates: [Date],
        daysInMonth: Int,
        previousEntryCount: Int?,
        calendar: Calendar = .current
    ) {
        self.sector = sector
        self.entryDates = entryDates
        self.daysInMonth = daysInMonth
        self.previousEntryCount = previousEntryCount
        self.calendar = calendar
    }

    public func evidence() -> Evidence {
        guard !entryDates.isEmpty, daysInMonth > 0 else { return Evidence() }

        // Distinct days, not entries: twelve entries on one afternoon is one
        // day of reflection, and counting them separately would flatter it.
        let daysWritten = Set(entryDates.map { calendar.startOfDay(for: $0) }).count

        var rows = [
            EvidenceRow(
                label: "days written",
                value: "\(daysWritten)/\(daysInMonth)",
                normalised: Double(daysWritten) / Double(daysInMonth),
                weight: 2
            )
        ]

        if let previousEntryCount, previousEntryCount > 0 {
            let change = Double(entryDates.count - previousEntryCount) / Double(previousEntryCount)
            rows.append(EvidenceRow(
                label: "vs last month",
                value: "\(change >= 0 ? "+" : "")\(Int((change * 100).rounded()))%",
                normalised: 0.5 + change / 2,  // Relies on EvidenceRow clamping above 1.0 when writing more than last month
                weight: 1
            ))
        }

        return Evidence(rows)
    }
}
