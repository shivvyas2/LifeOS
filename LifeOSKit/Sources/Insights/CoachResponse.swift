import Foundation

/// A small, deterministic presentation grammar. Values are never inferred or
/// recalculated: a table cell displays exactly what the answer supplied.
public struct CoachResponse: Equatable, Sendable {
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        case heading(String)
        case list([String])
        case table(headers: [String], rows: [[String]])
    }
    public let blocks: [Block]

    public init(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var output: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }
            if index + 1 < lines.count,
               let headers = Self.cells(line), headers.count >= 2,
               let separator = Self.cells(lines[index + 1]),
               separator.count == headers.count,
               separator.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) {
                var rows: [[String]] = []
                var next = index + 2
                while next < lines.count, let cells = Self.cells(lines[next]), cells.count == headers.count {
                    rows.append(cells)
                    next += 1
                }
                if !rows.isEmpty {
                    output.append(.table(headers: headers, rows: rows))
                    index = next
                    continue
                }
            }
            if let range = line.range(of: "^#{1,3} +", options: .regularExpression) {
                output.append(.heading(String(line[range.upperBound...])))
                index += 1
                continue
            }
            if Self.listItem(line) != nil {
                var items: [String] = []
                while index < lines.count, let item = Self.listItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                output.append(.list(items))
                continue
            }
            // Unrecognized or incomplete structures stay readable as text.
            output.append(.paragraph(line))
            index += 1
        }
        blocks = output
    }

    private static func listItem(_ line: String) -> String? {
        guard let range = line.range(of: "^(?:[-*•] |[0-9]+[.)] )", options: .regularExpression) else { return nil }
        return String(line[range.upperBound...])
    }

    private static func cells(_ line: String) -> [String]? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }
        var result: [String] = [], cell = "", escaped = false
        for character in trimmed {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "|" {
                result.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        return result.count >= 2 ? result : nil
    }
}

public enum CoachPresentation {
    public static let marker = "LIFEOS_STRUCTURED_COACH_V1"
    public static let instruction = """
    LIFEOS_STRUCTURED_COACH_V1
    Lead with the useful answer in one or two short sentences. Usually keep the
    entire reply under 120 words; use more only when the person asks for detail.
    No greeting, filler, motivational speech, repeated summary, or routine follow-up question.
    Use only supplied facts and figures, including units and time periods. Never
    invent missing values or turn missing data into zero. State uncertainty briefly.
    Choose the structure that fits this question; do not force every answer into a template:
    - A simple question needs just a short paragraph.
    - Two or more metrics: a Markdown table with Metric and Value columns.
    - Comparisons, spending categories, or dated readings: a Markdown table with
      meaningful headers, at most four columns and six rows unless asked for detail.
    - Actions: up to three short bullets, one concrete step each.
    Optional short ## headings label distinct sections. At most three sections.
    Do not repeat table values in prose. Keep cells short. Escape literal pipes
    inside cells as \\|. Never output JSON, HTML, code fences, or decorative symbols.
    Ask one concise question only when essential information is missing.
    """

    /// Added behind `instruction` only when the reply will be read aloud.
    ///
    /// The voice gets its own passages rather than a flattening of the
    /// tables, because a table read out is a robot and a sentence said is a
    /// person. The opening is asked for first so it is the first thing to
    /// arrive: the voice starts on it while the rest is still being written,
    /// and each later passage lets its section onto the screen as it plays.
    public static let spokenTrackInstruction = """
    Your reply will be spoken aloud and shown on screen, and the two parts are different.
    The spoken parts are you talking, not text being read. Talk the way you would to a friend \
    across a table: contractions, short sentences, one thought at a time, a reaction before a \
    number (that's a good week), and figures said the way people say them out loud (seven hours \
    twenty minutes, seventy-two percent), never as they are written in a table. Never read the \
    screen out; say what it means, and mention it only naturally (I've put the numbers up for you).
    Begin with exactly one line that starts with \(SpokenTrack.prefix) followed by the opening: \
    one or two sentences, at most one figure, no markdown, no list, no table, no quotation marks.
    Then a blank line, then the written answer following the rules above, in sections.
    Before each later section you may add one more line starting with \(SpokenTrack.prefix): \
    one or two sentences that say what that section shows and why it matters, again with at \
    most one figure and no markdown. It must not repeat the section's cells or sentences word \
    for word. At most four \(SpokenTrack.prefix) lines in the whole reply, each under 220 \
    characters. The written answer must not repeat any \(SpokenTrack.prefix) line word for word.
    """

    public static func isStructured(_ instructions: String) -> Bool { instructions.contains(marker) }

    public static func clean(_ text: String, instructions: String) -> String {
        isStructured(instructions) ? text.trimmingCharacters(in: .whitespacesAndNewlines) : ResponseStyle.clean(text)
    }
}
