import Foundation

/// One reply, two audiences.
///
/// The model writes a first line for the voice and everything after it for
/// the screen. Splitting them on the phone rather than asking for two
/// completions keeps one call, one debit and one set of figures, and it lets
/// the voice start the moment its line has arrived instead of when the last
/// table row has.
///
/// Built from partial text as well as whole text, because a stream spends
/// most of its life half arrived. `isSpokenLinePending` is the state in which
/// nothing is yet known: the text so far is still inside the spoken line, or
/// is too short to tell whether there is one.
public struct SpokenReply: Equatable, Sendable {
    /// What opens the line the voice reads. Matched without regard to case
    /// or leading whitespace, since a model that gets the word right and the
    /// case wrong has still done what it was asked.
    public static let prefix = "SAY:"

    /// The spoken line, cleaned for a voice. Nil until the line is complete,
    /// and nil when there is none.
    public let spoken: String?
    /// What the screen renders. Empty while the spoken line is still arriving.
    public let shown: String
    /// True while the text could still turn out to begin with a spoken line.
    public let isSpokenLinePending: Bool

    public init(parsing text: String) {
        // Leading blank lines are the model clearing its throat, not content.
        let trimmed = String(text.drop(while: { $0.isNewline || $0 == " " }))

        guard let firstNewline = trimmed.firstIndex(where: \.isNewline) else {
            // One line so far. Either it is the spoken line still being
            // written, or it is a short whole answer with no spoken line.
            if Self.couldBecomePrefix(trimmed) || Self.hasPrefix(trimmed) {
                spoken = nil
                shown = ""
                isSpokenLinePending = true
            } else {
                spoken = nil
                shown = trimmed
                isSpokenLinePending = false
            }
            return
        }

        let firstLine = String(trimmed[..<firstNewline])
        guard Self.hasPrefix(firstLine) else {
            spoken = nil
            shown = trimmed
            isSpokenLinePending = false
            return
        }

        let line = Self.cleanSpoken(String(firstLine.dropFirst(Self.prefix.count)))
        spoken = line.isEmpty ? nil : line
        shown = String(trimmed[trimmed.index(after: firstNewline)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        isSpokenLinePending = false
    }

    private static func hasPrefix(_ line: String) -> Bool {
        line.uppercased().hasPrefix(prefix)
    }

    private static func couldBecomePrefix(_ line: String) -> Bool {
        line.count < prefix.count && prefix.hasPrefix(line.uppercased())
    }

    /// The line as a voice should get it: no markup, no dashes, and no
    /// quotation marks around the whole thing, which a model adds when told
    /// to write what it would say.
    private static func cleanSpoken(_ raw: String) -> String {
        ResponseStyle.clean(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
