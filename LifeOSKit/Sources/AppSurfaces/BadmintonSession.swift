import Foundation

/// What a badminton session was: a match with a score, or practice.
///
/// Carried in the live packets, in the watch's final summary and on the saved
/// workout, so it is validated like everything else that crosses the wire.
public struct BadmintonSession: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case match, practice }
    public enum Format: String, Codable, Sendable, CaseIterable { case singles, doubles }

    public var kind: Kind
    public var format: Format
    /// The partner in doubles. Nil in singles, and nil when not given.
    public var teammate: String?
    /// One name in singles, up to two in doubles; may be empty.
    public var opponents: [String]
    /// The match score. Nil for practice.
    public var score: BadmintonScore?
    /// What a practice session worked on ("Net play", "Smash defence").
    public var focus: String?

    public static let nameLimit = 40

    public init(kind: Kind = .match, format: Format = .singles, teammate: String? = nil,
                opponents: [String] = [], focus: String? = nil, firstServer: BadmintonSide = .us) {
        self.kind = kind; self.format = format
        self.teammate = format == .doubles ? Self.clean(teammate) : nil
        self.opponents = opponents.compactMap(Self.clean).prefix(format == .doubles ? 2 : 1).map { $0 }
        self.focus = kind == .practice ? Self.clean(focus) : nil
        self.score = kind == .match ? BadmintonScore(firstServer: firstServer) : nil
    }

    /// Trimmed, length-capped, and nil when nothing is left.
    public static func clean(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(nameLimit))
    }

    /// Records a rally on a match. Practice has no score and ignores it.
    public mutating func record(_ winner: BadmintonSide) { score?.record(winner) }
    public mutating func undo() { score?.undo() }

    /// The line a list or a notification uses: "Won 21-17 18-21 21-15" or
    /// "Practice · Net play".
    public var summary: String {
        guard kind == .match, let score else {
            return focus.map { "Practice · \($0)" } ?? "Practice"
        }
        let games = score.games.map { "\($0.us)-\($0.them)" }
        let current = score.current == BadmintonGame() ? [] : ["\(score.current.us)-\(score.current.them)"]
        let line = (games + current).joined(separator: " ")
        let outcome = score.winner.map { $0 == .us ? "Won" : "Lost" } ?? "Unfinished"
        return line.isEmpty ? outcome : "\(outcome) \(line)"
    }

    public var isValid: Bool {
        let names = ([teammate].compactMap { $0 } + opponents + [focus].compactMap { $0 })
        return names.allSatisfy { !$0.isEmpty && $0.count <= Self.nameLimit }
            && opponents.count <= (format == .doubles ? 2 : 1)
            && (format == .doubles || teammate == nil)
            && (kind == .match) == (score != nil)
            && (kind == .practice || focus == nil)
            && (score?.isValid ?? true)
    }
}

extension BadmintonSession {
    /// The same setup with a zero score: what a new workout starts from when
    /// it reuses last time's partner and opponents.
    public var fresh: BadmintonSession {
        BadmintonSession(kind: kind, format: format, teammate: teammate, opponents: opponents,
                         focus: focus, firstServer: score?.firstServer ?? .us)
    }
}
