import Foundation

/// Turns the short forms a screen uses into the words a person says.
///
/// A synthesiser given "7h 24m" says "seven h twenty four m", and "72%" as
/// "seventy two" with a swallowed sign; both are the sound of text being read
/// out rather than something being said. The passages the model writes are
/// mostly already spoken English, but a figure copied from a table slips
/// through, and this catches it before the voice does.
public enum SpokenForm {
    public static func normalize(_ text: String) -> String {
        rules.reduce(text) { partial, rule in replace(partial, rule.regex, rule.make) }
    }

    /// One substitution: a compiled pattern and what to make of its groups.
    /// `NSRegularExpression` is immutable and thread-safe, which is what the
    /// unchecked conformance vouches for.
    private struct Rule: @unchecked Sendable {
        let regex: NSRegularExpression
        let make: @Sendable ([String]) -> String
        init(_ regex: NSRegularExpression, _ make: @escaping @Sendable ([String]) -> String) {
            self.regex = regex; self.make = make
        }
    }

    /// Compiled once: `normalize` runs on every streamed chunk.
    private static let rules: [Rule] = [
        // Hours and minutes together, then alone.
        Rule(compile(#"(\d+)h\s*(\d+)m\b"#), { g in
            "\(g[0]) \(plural(g[0], "hour")) \(Int(g[1]).map(String.init) ?? g[1]) \(plural(g[1], "minute"))" }),
        Rule(compile(#"(\d+)h\b"#), { g in "\(g[0]) \(plural(g[0], "hour"))" }),
        Rule(compile(#"(\d+)\s*min\b"#), { g in "\(g[0]) \(plural(g[0], "minute"))" }),
        Rule(compile(#"(\d+(?:\.\d+)?)%"#), { g in "\(g[0]) percent" }),
        Rule(compile(#"\s*/\s*day\b"#), { _ in " a day" }),
        Rule(compile(#"(\d+(?:\.\d+)?)\s*kg\b"#), { g in "\(g[0]) \(plural(g[0], "kilogram"))" }),
        Rule(compile(#"(\d+(?:\.\d+)?)\s*km\b"#), { g in "\(g[0]) \(plural(g[0], "kilometre"))" }),
        Rule(compile(#"(\d+)\s*bpm\b"#), { g in "\(g[0]) beats per minute" }),
        Rule(compile(#"(\d+)\s*ms\b"#), { g in "\(g[0]) milliseconds" }),
        Rule(compile(#"(\d+)\s*-\s*(\d+)"#), { g in "\(g[0]) to \(g[1])" }),
        Rule(compile(#"\s*·\s*"#), { _ in ", " }),
    ]

    private static func compile(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals above; a typo there is a programming
        // error, not a runtime condition.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func plural(_ value: String, _ unit: String) -> String {
        (Double(value) == 1) ? unit : unit + "s"
    }

    /// Replaces each match with what the closure makes of its capture groups.
    private static func replace(_ text: String, _ regex: NSRegularExpression, _ make: ([String]) -> String) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            var groups: [String] = []
            for index in 1..<max(match.numberOfRanges, 1) {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            out += make(groups)
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }
}
