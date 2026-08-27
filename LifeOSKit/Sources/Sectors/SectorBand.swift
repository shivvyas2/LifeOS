import Foundation
import Persistence

/// One sector's month in flight: where it closes if nothing changes, where it
/// closes if the remaining days are perfect, and the reasoning behind both.
///
/// Both ends come out of `SectorEvidenceFactory`, the same call the close
/// makes. That is the whole design: a band cannot disagree with the close
/// that follows it, because there is only one piece of arithmetic.
public struct SectorBand: Sendable, Equatable, Identifiable {
    public let sector: LifeSector
    /// Where the month closes if the rest of it matches the part already
    /// lived. Nil when the sector has no evidence at all, never zero.
    public let floor: Int?
    /// Where the month closes if every remaining day hits the person's
    /// targets. Nil when no ceiling is defensible: see `money` below.
    public let ceiling: Int?
    public let floorEvidence: Evidence
    public let ceilingEvidence: Evidence

    public var id: LifeSector { sector }

    /// The share of the score that can no longer move, 0...1. Nil when there
    /// is no band to speak of.
    public var decided: Double? {
        guard let floor, let ceiling else { return nil }
        return min(max(1 - Double(ceiling - floor) / 10, 0), 1)
    }

    /// How the range reads: nil when nothing has been judged, a single
    /// number when the band has collapsed or has no ceiling, and the two
    /// ends otherwise. One rule, because three views render it and a
    /// fourth will.
    public var rangeText: String? {
        guard let floor else { return nil }
        guard let ceiling, ceiling != floor else { return String(floor) }
        return "\(floor)–\(ceiling)"
    }

    public static func band(
        for sector: LifeSector,
        inputs: MonthInputs,
        progress: MonthProgress,
        answers: [String: String],
        calendar: Calendar = .current
    ) -> SectorBand {
        func score(_ projected: MonthInputs) -> Evidence {
            SectorEvidenceFactory.evidence(
                for: sector, inputs: projected, answers: answers, calendar: calendar
            )
        }

        let floorEvidence = score(
            ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)
        )
        let ceilingEvidence = score(
            ProjectedInputs.perfect(inputs, progress: progress, calendar: calendar)
        )

        let floor = floorEvidence.proposedScore
        var ceiling = ceilingEvidence.proposedScore

        // Money with no buckets has no ceiling. Nothing in the data says what
        // a good remaining spend would be: zero is a fantasy and any other
        // figure is invented. The card shows a floor and points at bucket
        // setup instead of making a number up.
        if sector == .money, inputs.budget == nil { ceiling = nil }

        // A ceiling below its floor is always a bug in a projection rather
        // than a fact about the month, and showing it would be worse than
        // clamping it.
        if let floor, let raised = ceiling { ceiling = max(floor, raised) }

        return SectorBand(
            sector: sector, floor: floor, ceiling: ceiling,
            floorEvidence: floorEvidence, ceilingEvidence: ceilingEvidence
        )
    }
}
