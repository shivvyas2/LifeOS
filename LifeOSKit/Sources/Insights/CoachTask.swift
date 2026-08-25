import Foundation
import FoundationModels

/// Which model a task needs at minimum.
///
/// A task names a *floor*, not a model. The app never learns that a model has
/// a name — the mapping from role to model lives server-side, so changing it
/// is configuration rather than a release.
public enum Tier: Sendable, Equatable {
    case onDevice
    case cloud(Role)

    public enum Role: String, Sendable, Codable {
        case reasoning
        case vision
    }
}

/// One unit of coach work.
///
/// The output type is `Generable`, which is what lets a single declaration
/// serve both the on-device model and a cloud provider: the same type yields
/// a schema to send and decodes the reply that comes back.
public protocol CoachTask: Sendable {
    associatedtype Output: Generable

    var floor: Tier { get }

    /// Stable across requests. Anything that varies belongs in `prompt`.
    var instructions: String { get }

    func prompt(_ digest: MetricsDigest) -> String
}

public struct BriefTask: CoachTask {
    public typealias Output = DailyBrief

    public init() {}

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You read one person's health metrics and say what today looks like.
        Be specific and quantitative. Cite only numbers that appear in the
        data given to you; never estimate or invent one. If the data is thin,
        say less rather than padding.
        """
    }

    public func prompt(_ digest: MetricsDigest) -> String {
        """
        Here are the most recent days:

        \(digest.promptLines)

        Write today's brief.
        """
    }
}

public struct AnswerTask: CoachTask {
    public typealias Output = CoachAnswer

    public let question: String

    public init(question: String) {
        self.question = question
    }

    public let floor: Tier = .onDevice

    public var instructions: String {
        """
        You answer questions about one person's health metrics.
        Cite only numbers that appear in the data given to you. If the data
        does not contain the answer, say so plainly rather than guessing.
        """
    }

    public func prompt(_ digest: MetricsDigest) -> String {
        """
        Here are the most recent days:

        \(digest.promptLines)

        Question: \(question)
        """
    }
}
