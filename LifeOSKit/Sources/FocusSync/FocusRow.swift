import Foundation
import Persistence

/// `focus_sessions` on the wire. No user_id going up: the column defaults to
/// auth.uid(), so a client can never write a row as someone else.
struct FocusRow: Codable {
    let id: UUID
    let mood: String
    let source: String
    let started_at: Date
    let ended_at: Date?
    let focused_seconds: Int
    let blocks_completed: Int
    let project_task_id: UUID?

    init(_ s: FocusSessionSnapshot) {
        id = s.id; mood = s.mood; source = s.source; started_at = s.startedAt; ended_at = s.endedAt
        focused_seconds = Int(s.focusedSeconds.rounded()); blocks_completed = s.blocksCompleted
        project_task_id = s.projectTaskID
    }

    /// Written by hand so a nil end or task goes as `null`, not as a missing
    /// key: PostgREST refuses a bulk insert whose objects have different keys
    /// (PGRST102), and one session with a task among ones without would fail
    /// every upload after it.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(mood, forKey: .mood)
        try c.encode(source, forKey: .source)
        try c.encode(started_at, forKey: .started_at)
        try c.encode(ended_at, forKey: .ended_at)
        try c.encode(focused_seconds, forKey: .focused_seconds)
        try c.encode(blocks_completed, forKey: .blocks_completed)
        try c.encode(project_task_id, forKey: .project_task_id)
    }

    var snapshot: FocusSessionSnapshot {
        FocusSessionSnapshot(id: id, mood: mood, source: source, startedAt: started_at, endedAt: ended_at,
                             focusedSeconds: Double(focused_seconds), blocksCompleted: blocks_completed,
                             projectTaskID: project_task_id)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// PostgREST writes `2026-10-10T09:25:00.123456+00:00`: microseconds and
    /// an offset. The fraction is cut to milliseconds, which the system
    /// parser reads; a timestamp without one parses as it is.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseTimestamp(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return decoder
    }()

    static func parseTimestamp(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let digits = text[text.index(after: dot)...].prefix(while: \.isNumber)
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        let trimmed = text[..<dot] + "." + millis + text[digits.endIndex...]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: String(trimmed))
    }
}
