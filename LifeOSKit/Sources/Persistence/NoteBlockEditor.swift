import Foundation

/// The block operations a keystroke performs, as pure functions.
///
/// These are the rules that decide what Return and Backspace mean in a
/// document, and they are the part of the editor most likely to be subtly
/// wrong: merging before stripping a heading, losing a caret, renumbering a
/// list from the wrong place. Kept out of the view model so they can be tested
/// against a literal array instead of against a screen.
public enum NoteBlockEditor {

    /// What an edit produced: the new document, and where the caret should be.
    /// `focus` is nil when the caret should stay where it was.
    public struct Result: Equatable, Sendable {
        public var blocks: [NoteBlock]
        public var focus: UUID?
        /// False when the keystroke was not the editor's to consume, so UIKit
        /// should do whatever it would normally have done.
        public var handled: Bool

        public init(blocks: [NoteBlock], focus: UUID? = nil, handled: Bool = true) {
            self.blocks = blocks
            self.focus = focus
            self.handled = handled
        }
    }

    /// Return, pressed with the caret between `before` and `after`.
    ///
    /// On an empty list item this ends the list instead of extending it, which
    /// is how every editor worth using gets out of one: outdent a level if
    /// there is one to give up, otherwise fall back to a paragraph.
    public static func split(
        _ blocks: [NoteBlock], at id: UUID, before: String, after: String
    ) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        var blocks = blocks
        let current = blocks[index]

        if current.kind.continuesOnReturn, before.isEmpty, after.isEmpty {
            if current.indent > 0 {
                blocks[index].indent -= 1
            } else {
                blocks[index].kind = .paragraph
            }
            return Result(blocks: blocks, focus: id)
        }

        blocks[index].text = before

        // A list continues itself and keeps its indent; anything else drops to
        // a paragraph at the left margin, because nobody wants a second
        // heading straight after the first.
        let continues = current.kind.continuesOnReturn
        let new = NoteBlock(
            kind: continues ? current.kind : .paragraph,
            text: after,
            indent: continues ? current.indent : 0
        )
        blocks.insert(new, at: index + 1)
        return Result(blocks: blocks, focus: new.id)
    }

    /// Backspace with the caret at offset zero.
    ///
    /// The order is the whole rule and it matches what people expect: strip the
    /// indent first, then the block kind, and only then merge into the block
    /// above. Merging first would make it impossible to turn a heading back
    /// into a paragraph without deleting it.
    public static func backspaceAtStart(_ blocks: [NoteBlock], at id: UUID) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        var blocks = blocks

        if blocks[index].indent > 0 {
            blocks[index].indent -= 1
            return Result(blocks: blocks, focus: id)
        }
        if blocks[index].kind != .paragraph {
            blocks[index].kind = .paragraph
            return Result(blocks: blocks, focus: id)
        }
        // The first block of a document has nothing above it to merge into, so
        // the keystroke is not ours and UIKit keeps whatever it would have done.
        guard index > 0 else { return Result(blocks: blocks, handled: false) }

        // Backspacing into a block with no text deletes it, since there is
        // nothing to merge with. A sketch counts only when it is still blank:
        // deleting someone's drawing because they held Backspace would be
        // unrecoverable.
        let above = blocks[index - 1]
        if above.kind == .divider || above.isBlankSketch {
            blocks.remove(at: index - 1)
            return Result(blocks: blocks, focus: id)
        }
        if above.kind == .sketch {
            // A drawn sketch stops the merge rather than being swallowed.
            return Result(blocks: blocks, handled: false)
        }

        let removed = blocks.remove(at: index)
        blocks[index - 1].text += removed.text
        return Result(blocks: blocks, focus: blocks[index - 1].id)
    }

    public static func indent(_ blocks: [NoteBlock], at id: UUID, by delta: Int) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        let next = blocks[index].indent + delta
        guard next >= 0, next <= NoteBlock.maxIndent else {
            return Result(blocks: blocks, handled: false)
        }
        var blocks = blocks
        blocks[index].indent = next
        return Result(blocks: blocks, focus: id)
    }

    /// Applies a block kind, whether it came from a typed markdown prefix or
    /// from the slash menu.
    ///
    /// A divider is the exception: it holds no text and cannot take the caret,
    /// so it is inserted with an empty paragraph behind it for the caret to
    /// land in. Without that, typing `---` would strand the person.
    public static func transform(
        _ blocks: [NoteBlock], at id: UUID, to kind: NoteBlockKind, text: String
    ) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        var blocks = blocks

        // Neither a rule nor a sketch holds text, so both are followed by an
        // empty paragraph for the caret. Without it, typing `---` or picking
        // Sketch from the menu strands the person with nowhere to type.
        if !kind.isTextual {
            blocks[index] = NoteBlock(kind: kind)
            let paragraph = NoteBlock()
            blocks.insert(paragraph, at: index + 1)
            return Result(blocks: blocks, focus: paragraph.id)
        }

        blocks[index].kind = kind
        blocks[index].text = text
        return Result(blocks: blocks, focus: id)
    }

    /// A kind picked from the bar for a block that already has words: the
    /// kind changes, the words stay. The slash menu's pick goes through
    /// `transform` with an empty string instead, since what was typed there
    /// was a command rather than content.
    public static func changeKind(_ blocks: [NoteBlock], at id: UUID, to kind: NoteBlockKind) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        return transform(blocks, at: id, to: kind, text: blocks[index].text)
    }

    /// The title field takes Return as a newline before the editor hears of
    /// it; the editor reads it as "go to the body". The title without its
    /// newlines when one was typed, nil when none was.
    public static func titleWithoutReturn(_ title: String) -> String? {
        guard title.contains(where: \.isNewline) else { return nil }
        return title.filter { !$0.isNewline }
    }

    public static func toggleCheck(_ blocks: [NoteBlock], at id: UUID) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        var blocks = blocks
        blocks[index].isChecked.toggle()
        return Result(blocks: blocks)
    }

    /// Closes an open `[[` with the chosen page title.
    ///
    /// The brackets are closed here rather than left for the person, so the
    /// link is live the moment it is picked instead of after they remember to
    /// finish it.
    public static func completeLink(
        _ blocks: [NoteBlock], at id: UUID, with title: String
    ) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        let text = blocks[index].text
        guard let open = text.range(of: "[[", options: .backwards) else {
            return Result(blocks: blocks, handled: false)
        }
        var blocks = blocks
        blocks[index].text = String(text[..<open.upperBound]) + title + "]]"
        return Result(blocks: blocks, focus: id)
    }

    /// The number each numbered block shows.
    ///
    /// A run restarts after any block that is not numbered, which is what makes
    /// two separate lists on one page number themselves separately instead of
    /// continuing each other.
    public static func ordinals(_ blocks: [NoteBlock]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var run = 0
        for block in blocks {
            if block.kind == .numbered {
                run += 1
                result[block.id] = run
            } else {
                run = 0
            }
        }
        return result
    }

    /// The text after a "/" that begins a block, or nil when there is no menu
    /// to show. A slash mid-sentence is a date or a path, not a command, and a
    /// space ends the command.
    public static func slashQuery(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let query = String(text.dropFirst())
        return query.contains(" ") ? nil : query
    }

    /// The partial title inside an unclosed `[[` to the left of the caret, or
    /// nil when the brackets are already closed, so the picker does not reopen
    /// every time the caret passes a finished link.
    public static func linkQuery(in text: String, caret: Int) -> String? {
        let nsText = text as NSString
        let bounded = max(0, min(caret, nsText.length))
        let prefix = nsText.substring(to: bounded)

        guard let open = prefix.range(of: "[[", options: .backwards) else { return nil }
        let tail = String(prefix[open.upperBound...])
        guard !tail.contains("]]"), !tail.contains("\n") else { return nil }
        return tail
    }
}


public extension NoteBlockEditor {
    /// Stores a sketch's ink.
    static func setDrawing(_ blocks: [NoteBlock], at id: UUID, drawing: Data?) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }),
              blocks[index].kind == .sketch
        else { return Result(blocks: blocks, handled: false) }

        var blocks = blocks
        // Empty ink is stored as nil rather than as an empty drawing, so
        // "has this been drawn in" stays one question with one answer.
        blocks[index].drawing = (drawing?.isEmpty ?? true) ? nil : drawing
        return Result(blocks: blocks)
    }

    /// Resizes a sketch, clamped to the bounds a sketch is useful between.
    static func setSketchHeight(_ blocks: [NoteBlock], at id: UUID, height: Double) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }),
              blocks[index].kind == .sketch
        else { return Result(blocks: blocks, handled: false) }

        var blocks = blocks
        blocks[index].sketchHeight = min(
            max(height, NoteBlock.minSketchHeight), NoteBlock.maxSketchHeight
        )
        return Result(blocks: blocks)
    }
}
