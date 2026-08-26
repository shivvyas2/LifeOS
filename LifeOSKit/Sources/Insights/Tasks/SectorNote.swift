import Foundation
import FoundationModels
import Persistence

/// One sentence about what changed in a sector this month.
@Generable
public struct SectorNote: Equatable, Sendable {

    @Guide(description: "One or two sentences describing what changed this month. Plain and specific. No advice, no encouragement, no score.")
    public var summary: String
}

/// Everything the model is allowed to see about a sector-month.
///
/// Deliberately only the rows the rule actually used, so the sentence cannot
/// cite a figure that played no part in the number.
///
/// `previousUserScore` is carried on the context but deliberately does not
/// reach `promptLines`. The instructions already forbid the model from
/// mentioning a score; feeding it last month's number on the same 0-10 scale
/// works against that instruction instead of with it. The close screen shows
/// "Last month you said N" on its own, so the model does not need to.
public struct SectorEvidenceContext: Sendable {
    public let sectorTitle: String
    public let rows: [EvidenceRow]
    public let previousUserScore: Int?

    public init(sectorTitle: String, rows: [EvidenceRow], previousUserScore: Int?) {
        self.sectorTitle = sectorTitle
        self.rows = rows
        self.previousUserScore = previousUserScore
    }

    public var promptLines: String {
        let lines = rows.map { "\($0.label): \($0.value)" }
        return lines.isEmpty ? "no data recorded" : lines.joined(separator: "\n")
    }
}

public struct SectorNoteTask: CoachTask {
    /// On-device only: the note is written against evidence that never leaves
    /// the phone, so there is no server-side name for it.
    public let remoteName: String? = nil

    public typealias Output = SectorNote
    public typealias Context = SectorEvidenceContext

    public let sectorTitle: String

    public init(sectorTitle: String) {
        self.sectorTitle = sectorTitle
    }

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You describe one month in one area of a person's life, from figures
        already computed for you. Cite only figures you are given; never
        estimate or invent one. Never propose or mention a score, and never
        give advice. If the figures are thin, say less rather than padding.
        """
    }

    public func prompt(_ context: Context, for audience: MetricsDigest.Audience) -> String {
        """
        Area: \(context.sectorTitle)

        \(context.promptLines)

        Describe what changed this month.
        """
    }
}

/// Decoded from the Edge Function's JSON as well as generated on-device.
/// The conformance is declared in this file so Swift can synthesise it from
/// the stored properties; an extension in another file cannot.
extension SectorNote: Decodable {}
