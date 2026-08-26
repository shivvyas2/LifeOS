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
    /// `Decodable` as well as `Generable`, because the same declaration has to
    /// serve two very different callers: the on-device model, which yields a
    /// schema and decodes through `Generable`, and the cloud function, which
    /// returns plain JSON. Constraining it here rather than casting at the
    /// call site is what lets `RemoteEngine.run` stay generic.
    associatedtype Output: Generable & Decodable
    /// What this task needs to see. Was fixed at `MetricsDigest`, which made
    /// any task about something other than health metrics inexpressible.
    associatedtype Context: Sendable

    var floor: Tier { get }

    /// The server-side name of this task, or nil when it never leaves the
    /// device. The model and schema behind a name live in the Edge Function,
    /// so changing which model answers a task is a deploy rather than a
    /// release.
    var remoteName: String? { get }

    /// Stable across requests. Anything that varies belongs in `prompt`.
    var instructions: String { get }

    /// Renders the context for a given audience. `.onDevice` may carry raw
    /// series; `.offDevice` must never, which is why the audience is a
    /// parameter here rather than a policy inside each engine.
    func prompt(_ context: Context, for audience: MetricsDigest.Audience) -> String
}

public struct BriefTask: CoachTask {
    public typealias Output = DailyBrief
    public typealias Context = MetricsDigest

    public init() {}

    public let floor: Tier = .onDevice
    // The brief is a later slice; nothing serves it in the cloud yet.
    public let remoteName: String? = nil

    public var instructions: String {
        """
        You read one person's health metrics and say what today looks like.
        Be specific and quantitative. Cite only numbers that appear in the
        data given to you; never estimate or invent one. If the data is thin,
        say less rather than padding.
        """
    }

    public func prompt(_ digest: MetricsDigest, for audience: MetricsDigest.Audience) -> String {
        """
        Here are the most recent days:

        \(digest.promptLines(for: audience))

        Write today's brief.
        """
    }
}

public struct AnswerTask: CoachTask {
    public typealias Output = CoachAnswer
    public typealias Context = ContextBundle

    public let question: String

    public init(question: String) {
        self.question = question
    }

    public let floor: Tier = .onDevice
    public let remoteName: String? = "answer"

    public var instructions: String {
        """
        You answer questions about one person's life: their health metrics,
        money, and life-sector scores.
        Cite only numbers that appear in the data given to you. If the data
        does not contain the answer, say so plainly rather than guessing.
        """
    }

    public func prompt(_ bundle: ContextBundle, for audience: MetricsDigest.Audience) -> String {
        """
        Here is what their data shows:

        \(bundle.promptLines(for: audience))

        Question: \(question)
        """
    }
}
