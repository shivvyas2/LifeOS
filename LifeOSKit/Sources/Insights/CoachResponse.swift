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

    public var spokenText: String {
        blocks.map { block in
            switch block {
            case .paragraph(let text), .heading(let text): return text
            case .list(let items): return items.joined(separator: ". ")
            case .table(let headers, let rows):
                return rows.map { row in
                    zip(headers, row).map { "\($0): \($1)" }.joined(separator: ", ")
                }.joined(separator: ". ")
            }
        }.joined(separator: "\n")
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

    public static func isStructured(_ instructions: String) -> Bool { instructions.contains(marker) }

    public static func clean(_ text: String, instructions: String) -> String {
        isStructured(instructions) ? text.trimmingCharacters(in: .whitespacesAndNewlines) : ResponseStyle.clean(text)
    }
}
