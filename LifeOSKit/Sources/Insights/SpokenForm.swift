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
        var out = text
        // Hours and minutes together, then alone.
        out = replace(out, #"(\d+)h\s*(\d+)m\b"#) { g in
            "\(g[0]) \(plural(g[0], "hour")) \(Int(g[1]).map(String.init) ?? g[1]) \(plural(g[1], "minute"))"
        }
        out = replace(out, #"(\d+)h\b"#) { g in "\(g[0]) \(plural(g[0], "hour"))" }
        out = replace(out, #"(\d+)\s*min\b"#) { g in "\(g[0]) \(plural(g[0], "minute"))" }
        out = replace(out, #"(\d+(?:\.\d+)?)%"#) { g in "\(g[0]) percent" }
        out = replace(out, #"\s*/\s*day\b"#) { _ in " a day" }
        out = replace(out, #"(\d+(?:\.\d+)?)\s*kg\b"#) { g in "\(g[0]) \(plural(g[0], "kilogram"))" }
        out = replace(out, #"(\d+(?:\.\d+)?)\s*km\b"#) { g in "\(g[0]) \(plural(g[0], "kilometre"))" }
        out = replace(out, #"(\d+)\s*bpm\b"#) { g in "\(g[0]) beats per minute" }
        out = replace(out, #"(\d+)\s*ms\b"#) { g in "\(g[0]) milliseconds" }
        out = replace(out, #"(\d+)\s*-\s*(\d+)"#) { g in "\(g[0]) to \(g[1])" }
        out = replace(out, #"\s*·\s*"#) { _ in ", " }
        return out
    }

    private static func plural(_ value: String, _ unit: String) -> String {
        (Double(value) == 1) ? unit : unit + "s"
    }

    /// Replaces each match with what the closure makes of its capture groups.
    private static func replace(_ text: String, _ pattern: String, _ make: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
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
