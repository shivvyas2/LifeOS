import Foundation

/// How the assistant is required to write, and the net that catches it when it
/// does not.
///
/// Two halves, because one is not enough. The instruction tells the model the
/// house style, which works most of the time; `clean(_:)` enforces it on the
/// way out, which works the rest of the time. Models drift back to markdown
/// the moment a list appears in the answer, and an instruction cannot be
/// relied on for something a person will notice on every single reply.
public enum ResponseStyle {

    /// Appended to every task's instructions.
    ///
    /// Written as prohibitions with reasons rather than a style sheet, because
    /// a model follows "never do X" far better than "prefer Y".
    public static let instruction = """
        Write in plain sentences, the way a person speaks.

        Never use markdown. No asterisks, no underscores, no backticks, no \
        hash headings, no bullet characters, no numbered lists. If you need to \
        list things, write them as a sentence separated by commas, or as \
        separate short sentences.

        Never use em dashes or en dashes. Use a comma, or start a new sentence.

        Never wrap words in quotation marks for emphasis. Apostrophes in \
        contractions are fine.

        Do not open with a greeting, a restatement of the question, or a \
        preamble about what you are about to do. Answer, then stop. If there \
        is nothing useful to say, say that in one sentence rather than padding.

        Give figures as figures with their units. Never invent one, and never \
        round a number you were given into a different number.
        """

    /// Strips what the instruction forbids.
    ///
    /// Deliberately conservative about two things a blunt filter gets wrong:
    /// apostrophes carry meaning inside contractions, and hyphens carry it
    /// inside words. "Don't" and "well-being" survive; a hyphen used as a
    /// bullet or as a dash between spaces does not.
    public static func clean(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines).map(cleanLine)

        // A reply that is nothing but blank lines after cleaning had no content
        // to begin with, and an empty bubble reads as a failure.
        lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return lines
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanLine(_ line: String) -> String {
        var result = line

        // A horizontal rule is markup with no words in it, so the whole line
        // goes. Checked before the bullet rule, which would otherwise see a
        // row of hyphens as a bullet with no text after it and keep it.
        if result.range(of: "^\\s*([-*_]\\s*){3,}$", options: .regularExpression) != nil {
            return ""
        }

        // Leading list markers, including the numbered kind. Done first, on the
        // line's own start, so a hyphen inside a sentence is left alone.
        result = result.replacingOccurrences(
            of: "^\\s*([-*+\u{2022}\u{2023}\u{25E6}\u{2043}]|\\d+[.)])\\s+",
            with: "",
            options: .regularExpression
        )
        // Hash headings.
        result = result.replacingOccurrences(of: "^\\s*#{1,6}\\s+", with: "", options: .regularExpression)
        // Block quotes.
        result = result.replacingOccurrences(of: "^\\s*>\\s?", with: "", options: .regularExpression)

        // Emphasis and code marks. The characters carry no meaning in prose, so
        // they are removed rather than replaced.
        for mark in ["**", "__", "*", "_", "`"] {
            result = result.replacingOccurrences(of: mark, with: "")
        }

        // Dashes used as punctuation. A spaced dash becomes a comma, which is
        // what it was standing in for; an unspaced one becomes a space, since
        // joining the words would invent a compound.
        result = result.replacingOccurrences(of: " \u{2014} ", with: ", ")
        result = result.replacingOccurrences(of: " \u{2013} ", with: ", ")
        result = result.replacingOccurrences(of: " - ", with: ", ")
        result = result.replacingOccurrences(of: "\u{2014}", with: " ")
        result = result.replacingOccurrences(of: "\u{2013}", with: " ")

        // Quotation marks, straight and curly. Apostrophes are left alone: an
        // apostrophe is a letter's business, not a quotation's.
        for quote in ["\"", "\u{201C}", "\u{201D}", "\u{00AB}", "\u{00BB}"] {
            result = result.replacingOccurrences(of: quote, with: "")
        }

        // Collapse the double spaces the removals leave behind, and the comma
        // pile-ups a spaced dash next to real punctuation can produce.
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: ",\\s*,", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([.,;:!?])", with: "$1", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespaces)
    }
}
