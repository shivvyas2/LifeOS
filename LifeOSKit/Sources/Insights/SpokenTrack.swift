import Foundation

/// One reply, two audiences, interleaved.
///
/// The model writes a `SAY:` passage for the voice before each section it
/// writes for the screen. Splitting them on the phone rather than asking for
/// two completions keeps one call, one debit and one set of figures, and it
/// lets the voice start on the opening while the sections are still arriving.
///
/// Built from partial text as well as whole text, because a stream spends
/// most of its life half arrived: a `SAY:` line is a passage only once its
/// newline has landed, and the opening is pending while the text so far could
/// still turn out to begin with the prefix.
public struct SpokenTrack: Equatable, Sendable {
    /// What opens a passage. Matched without regard to case or leading
    /// whitespace, since a model that gets the word right and the case wrong
    /// has still done what it was asked.
    public static let prefix = "SAY:"

    /// A passage and the sections it introduces. The opening's `shown` is
    /// usually empty; a segment whose passage was dropped by the cap has
    /// `spoken == nil` and reveals with the passage before it.
    public struct Segment: Equatable, Sendable {
        public let spoken: String?
        public let shown: String
        public init(spoken: String?, shown: String) { self.spoken = spoken; self.shown = shown }
    }

    public let segments: [Segment]
    /// True while the text could still turn out to begin with a passage.
    public let isOpeningPending: Bool

    /// The first passage, which the voice reads first.
    public var opening: String? { segments.first?.spoken }

    /// Everything the screen renders and the transcript stores.
    public var shownText: String {
        segments.map(\.shown).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Rendered blocks across every segment.
    public var blockCount: Int { revealedBlocks(throughSegment: segments.count - 1) }

    /// `final` says the text is the whole reply, so a trailing `SAY:` line
    /// without a newline is a complete passage rather than one still being
    /// written. A stream passes false; the finished reply passes true.
    public init(parsing text: String, final: Bool = false) {
        let trimmed = String(text.drop(while: { $0.isNewline || $0 == " " }))

        // One line so far: either the opening still being written, or a short
        // whole answer with no passage.
        if !trimmed.contains(where: \.isNewline) {
            if final, Self.hasPrefix(trimmed) {
                let passage = Self.cleanPassage(String(trimmed.trimmingCharacters(in: .whitespaces).dropFirst(Self.prefix.count)))
                segments = passage.isEmpty ? [] : [Segment(spoken: passage, shown: "")]
                isOpeningPending = false
            } else if Self.couldBecomePrefix(trimmed) || Self.hasPrefix(trimmed) {
                segments = []
                isOpeningPending = true
            } else {
                segments = [Segment(spoken: nil, shown: trimmed)]
                isOpeningPending = false
            }
            return
        }

        let endsWithNewline = trimmed.last?.isNewline == true
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // A trailing `SAY:` line without its newline is still being written,
        // unless the reply is final.
        if !final, !endsWithNewline, let last = lines.last, Self.hasPrefix(last) {
            lines.removeLast()
        }

        var built: [(spoken: String?, lines: [String])] = []
        for line in lines {
            if Self.hasPrefix(line) {
                let passage = Self.cleanPassage(String(line.trimmingCharacters(in: .whitespaces).dropFirst(Self.prefix.count)))
                // An empty passage is no passage: its sections join the
                // segment before, rather than opening a silent one.
                if passage.isEmpty, !built.isEmpty { continue }
                built.append((spoken: passage.isEmpty ? nil : passage, lines: []))
            } else if built.isEmpty {
                built.append((spoken: nil, lines: [line]))
            } else {
                built[built.count - 1].lines.append(line)
            }
        }

        segments = built.map { Segment(spoken: $0.spoken, shown: $0.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)) }
        isOpeningPending = false
    }

    private init(segments: [Segment], isOpeningPending: Bool) {
        self.segments = segments; self.isOpeningPending = isOpeningPending
    }

    /// Rendered blocks in segments `0...index`, which is how many the screen
    /// may show once segment `index` has begun to play.
    public func revealedBlocks(throughSegment index: Int) -> Int {
        guard index >= 0 else { return 0 }
        return segments.prefix(index + 1).reduce(0) { $0 + CoachResponse($1.shown).blocks.count }
    }

    /// The passages trimmed to a character budget, in order. A passage that
    /// would cross the budget is cut at the last sentence end that fits;
    /// passages after the budget is spent become nil, so their sections
    /// reveal with the passage before. The opening is never dropped: with a
    /// budget inside it, it keeps its first sentence.
    public func capped(to characters: Int = 700) -> SpokenTrack {
        var remaining = max(characters, 0)
        var out: [Segment] = []
        for (index, segment) in segments.enumerated() {
            guard let spoken = segment.spoken else { out.append(segment); continue }
            if spoken.count <= remaining {
                remaining -= spoken.count
                out.append(segment)
            } else if index == 0 {
                let kept = Self.cut(spoken, to: remaining, keepAtLeastOneSentence: true)
                remaining = max(0, remaining - kept.count)
                out.append(Segment(spoken: kept, shown: segment.shown))
            } else {
                let kept = Self.cut(spoken, to: remaining, keepAtLeastOneSentence: false)
                remaining = max(0, remaining - kept.count)
                out.append(Segment(spoken: kept.isEmpty ? nil : kept, shown: segment.shown))
            }
        }
        return SpokenTrack(segments: out, isOpeningPending: isOpeningPending)
    }

    /// Cuts on a sentence boundary within `limit`. With `keepAtLeastOneSentence`
    /// the first sentence survives even when it is longer than the limit; a
    /// voice that says nothing is worse than one that runs a little long.
    private static func cut(_ text: String, to limit: Int, keepAtLeastOneSentence: Bool) -> String {
        let clipped = String(text.prefix(limit))
        if let lastStop = clipped.lastIndex(where: { ".!?".contains($0) }) {
            return String(clipped[...lastStop]).trimmingCharacters(in: .whitespaces)
        }
        guard keepAtLeastOneSentence else { return "" }
        if let firstStop = text.firstIndex(where: { ".!?".contains($0) }) {
            return String(text[...firstStop])
        }
        return text
    }

    private static func hasPrefix(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix(prefix)
    }

    private static func couldBecomePrefix(_ line: String) -> Bool {
        line.count < prefix.count && prefix.hasPrefix(line.uppercased())
    }

    /// The passage as a voice should get it: no markup, no dashes, no
    /// quotation marks around the whole thing (which a model adds when told
    /// to write what it would say), and figures in the words a person says.
    private static func cleanPassage(_ raw: String) -> String {
        SpokenForm.normalize(ResponseStyle.clean(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
