import Foundation

/// What one line of a note is.
///
/// A block editor's whole trick is that the document is a list of small typed
/// pieces rather than one string with formatting hung off ranges. Splitting,
/// merging, reordering and turning a paragraph into a to-do all become list
/// operations, and none of them can corrupt the others.
public enum NoteBlockKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case paragraph
    case heading1, heading2, heading3
    case bulleted, numbered, todo
    case quote, callout, code
    case divider
    /// A drawing that takes its own space in the flow, as opposed to the
    /// page-wide ink layer that floats over everything.
    case sketch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paragraph: "Text"
        case .heading1:  "Heading 1"
        case .heading2:  "Heading 2"
        case .heading3:  "Heading 3"
        case .bulleted:  "Bulleted list"
        case .numbered:  "Numbered list"
        case .todo:      "To-do"
        case .quote:     "Quote"
        case .callout:   "Callout"
        case .code:      "Code"
        case .divider:   "Divider"
        case .sketch:    "Sketch"
        }
    }

    public var subtitle: String {
        switch self {
        case .paragraph: "Plain paragraph"
        case .heading1:  "Big section heading"
        case .heading2:  "Medium section heading"
        case .heading3:  "Small section heading"
        case .bulleted:  "A simple bulleted list"
        case .numbered:  "A list that numbers itself"
        case .todo:      "Track something with a checkbox"
        case .quote:     "Set a passage apart"
        case .callout:   "Make something stand out"
        case .code:      "Monospaced, no autocorrect"
        case .divider:   "A line between sections"
        case .sketch:    "Draw with a pencil, in line with the text"
        }
    }

    public var systemImage: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1:  "textformat.size.larger"
        case .heading2:  "textformat.size"
        case .heading3:  "textformat.size.smaller"
        case .bulleted:  "list.bullet"
        case .numbered:  "list.number"
        case .todo:      "checkmark.square"
        case .quote:     "text.quote"
        case .callout:   "lightbulb"
        case .code:      "chevron.left.forwardslash.chevron.right"
        case .divider:   "minus"
        case .sketch:    "scribble.variable"
        }
    }

    /// Whether the block owns editable text. A divider and a sketch do not,
    /// which is why neither can hold the caret and why the editor inserts a
    /// paragraph after each so there is somewhere to carry on typing.
    public var isTextual: Bool { self != .divider && self != .sketch }

    /// Whether Return inside the block continues it rather than dropping back
    /// to a paragraph. Lists continue; a heading does not, because nobody wants
    /// a second heading straight after the first.
    public var continuesOnReturn: Bool {
        switch self {
        case .bulleted, .numbered, .todo: true
        default: false
        }
    }

    /// The typed prefix that turns a paragraph into this block, Notion style.
    /// Nil for kinds only the slash menu offers.
    public var markdownPrefix: [String] {
        switch self {
        case .heading1:  ["# "]
        case .heading2:  ["## "]
        case .heading3:  ["### "]
        case .bulleted:  ["- ", "* ", "+ "]
        case .numbered:  ["1. ", "1) "]
        case .todo:      ["[] ", "[ ] ", "- [ ] "]
        case .quote:     ["> "]
        case .code:      ["```"]
        case .divider:   ["---", "***"]
        default:         []
        }
    }

    /// The blocks the slash menu offers, in menu order.
    public static var menuOrder: [NoteBlockKind] {
        [.paragraph, .heading1, .heading2, .heading3, .todo, .bulleted, .numbered,
         .quote, .callout, .code, .sketch, .divider]
    }

    /// The six kinds on the block picker's bar, in order, and the six behind
    /// its `More` menu. Together they are every kind once; a test holds
    /// them to it.
    public static var barOrder: [NoteBlockKind] {
        [.paragraph, .todo, .heading1, .bulleted, .numbered, .quote]
    }

    public static var moreOrder: [NoteBlockKind] {
        [.heading2, .heading3, .callout, .code, .sketch, .divider]
    }

    /// The word on a chip: shorter than the menu's title, so six fit a phone.
    public var chipTitle: String {
        switch self {
        case .paragraph: "Text"
        case .heading1:  "Heading"
        case .heading2:  "Heading 2"
        case .heading3:  "Heading 3"
        case .bulleted:  "Bullet"
        case .numbered:  "Numbered"
        case .todo:      "To-do"
        case .quote:     "Quote"
        case .callout:   "Callout"
        case .code:      "Code"
        case .divider:   "Divider"
        case .sketch:    "Sketch"
        }
    }
}

/// One line of a note.
///
/// A value type, and the document stores the whole array as JSON rather than as
/// a SwiftData relationship. Blocks are only ever read and written as a
/// document: no query asks for "every to-do block", and a relationship would
/// buy one migration hazard per block field in exchange for nothing.
public struct NoteBlock: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var kind: NoteBlockKind
    public var text: String
    /// To-do blocks only. Kept on every block so that ticking a to-do, turning
    /// it into a paragraph and back does not lose the tick.
    public var isChecked: Bool
    /// Nesting, 0 through 4. Purely visual indent: a nested list item is still
    /// a sibling in the array, which is what keeps every editing operation a
    /// flat list operation.
    public var indent: Int
    /// A `PKDrawing`, on sketch blocks only. Optional so the overwhelming
    /// majority of blocks, which are text, carry nothing.
    public var drawing: Data?
    /// How tall the sketch is. Stored because a person can drag it taller and
    /// the ink would otherwise be cropped differently on another device.
    public var sketchHeight: Double?
    /// When this to-do is meant to be done. To-do blocks only, and nil on
    /// every other kind. Authored, so it lives here rather than on the
    /// derived `NoteTask` row, which is rebuilt and would lose it.
    public var dueDate: Date?
    /// The goal this to-do counts towards, if any. Authored, for the same
    /// reason as `dueDate`.
    public var goalID: UUID?

    public init(
        id: UUID = UUID(),
        kind: NoteBlockKind = .paragraph,
        text: String = "",
        isChecked: Bool = false,
        indent: Int = 0,
        drawing: Data? = nil,
        sketchHeight: Double? = nil,
        dueDate: Date? = nil,
        goalID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isChecked = isChecked
        self.indent = min(max(indent, 0), NoteBlock.maxIndent)
        self.drawing = drawing
        self.sketchHeight = sketchHeight
        self.dueDate = dueDate
        self.goalID = goalID
    }

    /// Sketches start at a comfortable drawing height and can be dragged
    /// between these bounds. A sketch shorter than this is not worth the
    /// gesture; taller than this and it stops being inline.
    public static let defaultSketchHeight: Double = 220
    public static let minSketchHeight: Double = 120
    public static let maxSketchHeight: Double = 640

    public var resolvedSketchHeight: Double {
        min(max(sketchHeight ?? NoteBlock.defaultSketchHeight, NoteBlock.minSketchHeight),
            NoteBlock.maxSketchHeight)
    }

    /// True when a sketch block has never been drawn in, so the editor can
    /// prompt rather than showing an unexplained empty rectangle.
    public var isBlankSketch: Bool {
        kind == .sketch && (drawing?.isEmpty ?? true)
    }

    public static let maxIndent = 4

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Nothing anyone made: no words, no drawing, and not a rule, which is
    /// something put there on purpose even though it holds no text.
    public var holdsNothing: Bool {
        switch kind {
        case .sketch: isBlankSketch
        case .divider: false
        default: isEmpty
        }
    }

    /// A single empty paragraph: what a brand new note contains, and what is
    /// left behind when the last block is deleted. A document with no blocks at
    /// all has nowhere to put the caret.
    public static var blank: [NoteBlock] { [NoteBlock()] }
}

public enum NoteBlockParser {
    /// Resolves a Notion-style typed prefix.
    ///
    /// Returns the kind the block should become and the text left after the
    /// prefix is eaten, or nil when the text does not start with one. The
    /// editor calls this on every keystroke, so it is deliberately allocation
    /// light and never scans past the longest prefix.
    public static func shortcut(in text: String) -> (kind: NoteBlockKind, remainder: String)? {
        for (kind, prefix) in candidates where text.hasPrefix(prefix) {
            do {
                // `---` and ``` are whole-line markers rather than prefixes:
                // they fire only when nothing else has been typed, so a line
                // reading "--- and then some" stays a paragraph.
                if kind == .divider || kind == .code {
                    guard text == prefix else { continue }
                    return (kind, "")
                }
                return (kind, String(text.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    /// Every prefix, longest first.
    ///
    /// Order is the whole correctness argument: `- [ ] ` starts with `- `, so
    /// checking kinds in declaration order turns every to-do typed by hand into
    /// a bullet reading "[ ] whatever". Longest match first is the only rule
    /// that cannot be broken by adding a kind later.
    private static let candidates: [(NoteBlockKind, String)] = NoteBlockKind.allCases
        .flatMap { kind in kind.markdownPrefix.map { (kind, $0) } }
        .sorted { $0.1.count > $1.1.count }

    /// Renders blocks as Markdown, for share sheets and for the coach's
    /// context window. Round-tripping is not a goal: this is the lossy,
    /// readable direction.
    public static func markdown(_ blocks: [NoteBlock]) -> String {
        var numberedRun = 0
        var lines: [String] = []

        for block in blocks {
            let pad = String(repeating: "    ", count: block.indent)
            if block.kind != .numbered { numberedRun = 0 }

            switch block.kind {
            case .paragraph: lines.append(pad + block.text)
            case .heading1:  lines.append(pad + "# " + block.text)
            case .heading2:  lines.append(pad + "## " + block.text)
            case .heading3:  lines.append(pad + "### " + block.text)
            case .bulleted:  lines.append(pad + "- " + block.text)
            case .numbered:
                numberedRun += 1
                lines.append(pad + "\(numberedRun). " + block.text)
            case .todo:      lines.append(pad + (block.isChecked ? "- [x] " : "- [ ] ") + block.text)
            case .quote:     lines.append(pad + "> " + block.text)
            case .callout:   lines.append(pad + "> " + block.text)
            case .code:      lines.append(pad + "```\n" + block.text + "\n" + pad + "```")
            case .divider:   lines.append("---")
            // Markdown has no ink. Saying a drawing was here beats dropping it
            // silently, which would make an exported page look complete when
            // it is not.
            case .sketch:    lines.append(pad + "_[sketch]_")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Turns pasted or migrated Markdown into blocks. Used by the plan-entry
    /// migration and by paste, so a note pasted in from anywhere lands as
    /// editable blocks rather than as one wall of text.
    public static func blocks(fromMarkdown markdown: String) -> [NoteBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [NoteBlock] = []

        for line in lines {
            let indent = line.prefix { $0 == " " || $0 == "\t" }
                .reduce(0) { $0 + ($1 == "\t" ? 1 : 1) } / 4
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // Blank lines between paragraphs are the paragraph break, not
                // content. Two in a row would leave an empty block a user has
                // to backspace through.
                if blocks.last?.isEmpty == false { blocks.append(NoteBlock(indent: indent)) }
                continue
            }
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                blocks.append(NoteBlock(kind: .todo, text: String(trimmed.dropFirst(6)), isChecked: true, indent: indent))
                continue
            }
            if let (kind, remainder) = shortcut(in: trimmed), kind.isTextual {
                blocks.append(NoteBlock(kind: kind, text: remainder, indent: indent))
                continue
            }
            if trimmed == "---" || trimmed == "***" {
                blocks.append(NoteBlock(kind: .divider))
                continue
            }
            blocks.append(NoteBlock(kind: .paragraph, text: trimmed, indent: indent))
        }

        return blocks.isEmpty ? NoteBlock.blank : blocks
    }

    /// The first line of real text, used as a note's preview and as its title
    /// when the person never typed one.
    public static func excerpt(_ blocks: [NoteBlock], limit: Int = 160) -> String {
        let text = blocks
            .filter { $0.kind.isTextual && !$0.isEmpty }
            .map(\.text)
            .joined(separator: " ")
        return text.count <= limit ? text : String(text.prefix(limit)) + "..."
    }

    /// Open and done counts across every to-do in the document.
    public static func taskProgress(_ blocks: [NoteBlock]) -> (done: Int, total: Int) {
        let todos = blocks.filter { $0.kind == .todo }
        return (todos.filter(\.isChecked).count, todos.count)
    }
}

/// Obsidian's `[[wiki link]]`, which is what makes a pile of notes a graph
/// rather than a list of files.
public enum NoteLinkScanner {
    /// Every distinct link target in the text, in the order they appear.
    /// Case is preserved here and folded at lookup, so `[[Marathon]]` and
    /// `[[marathon]]` reach the same note without rewriting what was typed.
    public static func links(in text: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        var remainder = Substring(text)

        while let open = remainder.range(of: "[["),
              let close = remainder.range(of: "]]", range: open.upperBound..<remainder.endIndex) {
            let target = remainder[open.upperBound..<close.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            if !target.isEmpty, seen.insert(target.lowercased()).inserted {
                found.append(target)
            }
            remainder = remainder[close.upperBound...]
        }
        return found
    }

    public static func links(in blocks: [NoteBlock]) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for block in blocks {
            for link in links(in: block.text) where seen.insert(link.lowercased()).inserted {
                found.append(link)
            }
        }
        return found
    }

    /// The ranges to paint as links, for the editor's syntax highlighting.
    /// Returns the full `[[...]]` span so the brackets dim with the text.
    public static func ranges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchFrom = text.startIndex

        while let open = text.range(of: "[[", range: searchFrom..<text.endIndex),
              let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) {
            ranges.append(open.lowerBound..<close.upperBound)
            searchFrom = close.upperBound
        }
        return ranges
    }
}
