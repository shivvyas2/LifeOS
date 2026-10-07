import Testing
import Foundation
@testable import Persistence

@Suite struct NoteBlockEditorTests {

    private func doc(_ blocks: NoteBlock...) -> [NoteBlock] { blocks }

    // MARK: - Return

    @Test func returnAtTheEndOfALineStartsAnEmptyOneBelow() {
        let first = NoteBlock(text: "Hello")
        let result = NoteBlockEditor.split(doc(first), at: first.id, before: "Hello", after: "")

        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].text == "Hello")
        #expect(result.blocks[1].text == "")
        #expect(result.focus == result.blocks[1].id)
    }

    @Test func returnMidLineSplitsTheTextInTwo() {
        let first = NoteBlock(text: "Helloworld")
        let result = NoteBlockEditor.split(doc(first), at: first.id, before: "Hello", after: "world")

        #expect(result.blocks[0].text == "Hello")
        #expect(result.blocks[1].text == "world")
    }

    @Test func aListContinuesItselfOnReturn() {
        let item = NoteBlock(kind: .bulleted, text: "milk", indent: 2)
        let result = NoteBlockEditor.split(doc(item), at: item.id, before: "milk", after: "")

        #expect(result.blocks[1].kind == .bulleted)
        #expect(result.blocks[1].indent == 2)
    }

    /// Nobody wants a second heading straight after the first.
    @Test func aHeadingDoesNotContinueItself() {
        let heading = NoteBlock(kind: .heading1, text: "Title")
        let result = NoteBlockEditor.split(doc(heading), at: heading.id, before: "Title", after: "")

        #expect(result.blocks[1].kind == .paragraph)
    }

    /// The way out of a list: Return on an empty item ends it rather than
    /// adding another empty one.
    @Test func returnOnAnEmptyListItemEndsTheList() {
        let item = NoteBlock(kind: .todo)
        let result = NoteBlockEditor.split(doc(item), at: item.id, before: "", after: "")

        #expect(result.blocks.count == 1)
        #expect(result.blocks[0].kind == .paragraph)
    }

    /// A nested empty item gives up one level at a time before it gives up
    /// being a list at all.
    @Test func returnOnANestedEmptyItemOutdentsFirst() {
        let item = NoteBlock(kind: .bulleted, indent: 2)
        let result = NoteBlockEditor.split(doc(item), at: item.id, before: "", after: "")

        #expect(result.blocks[0].kind == .bulleted)
        #expect(result.blocks[0].indent == 1)
    }

    // MARK: - Backspace

    @Test func backspaceStripsTheIndentBeforeAnythingElse() {
        let block = NoteBlock(kind: .bulleted, text: "item", indent: 1)
        let result = NoteBlockEditor.backspaceAtStart(doc(block), at: block.id)

        #expect(result.handled)
        #expect(result.blocks[0].indent == 0)
        #expect(result.blocks[0].kind == .bulleted)
    }

    /// Stripping the kind has to come before merging, or a heading could never
    /// be turned back into a paragraph without deleting it.
    @Test func backspaceThenStripsTheBlockKind() {
        let block = NoteBlock(kind: .heading2, text: "Title")
        let result = NoteBlockEditor.backspaceAtStart(doc(block), at: block.id)

        #expect(result.blocks[0].kind == .paragraph)
        #expect(result.blocks[0].text == "Title")
    }

    @Test func backspaceOnAPlainParagraphMergesItIntoTheOneAbove() {
        let above = NoteBlock(text: "Hello ")
        let below = NoteBlock(text: "world")
        let result = NoteBlockEditor.backspaceAtStart(doc(above, below), at: below.id)

        #expect(result.blocks.count == 1)
        #expect(result.blocks[0].text == "Hello world")
        #expect(result.focus == above.id)
    }

    /// A rule has no text to merge with, so backspacing past it removes the
    /// rule and leaves the paragraph alone.
    @Test func backspaceThroughARuleDeletesTheRule() {
        let rule = NoteBlock(kind: .divider)
        let below = NoteBlock(text: "after")
        let result = NoteBlockEditor.backspaceAtStart(doc(rule, below), at: below.id)

        #expect(result.blocks.count == 1)
        #expect(result.blocks[0].text == "after")
    }

    /// Nothing above to merge into, so the keystroke belongs to UIKit.
    @Test func backspaceInTheFirstBlockIsNotOurs() {
        let only = NoteBlock(text: "start")
        let result = NoteBlockEditor.backspaceAtStart(doc(only), at: only.id)

        #expect(result.handled == false)
        #expect(result.blocks.count == 1)
    }

    @Test func backspaceMergesTheWholeTailNotJustTheFirstWord() {
        let above = NoteBlock(text: "one")
        let below = NoteBlock(kind: .paragraph, text: " two three")
        let result = NoteBlockEditor.backspaceAtStart(doc(above, below), at: below.id)

        #expect(result.blocks[0].text == "one two three")
    }

    // MARK: - Indent

    @Test func indentStopsAtTheDeepestAllowedLevel() {
        let block = NoteBlock(kind: .bulleted, indent: NoteBlock.maxIndent)
        let result = NoteBlockEditor.indent(doc(block), at: block.id, by: 1)

        #expect(result.handled == false)
    }

    @Test func outdentStopsAtTheMargin() {
        let block = NoteBlock(kind: .bulleted, indent: 0)
        #expect(NoteBlockEditor.indent(doc(block), at: block.id, by: -1).handled == false)
    }

    // MARK: - Transform

    @Test func transformKeepsTheTextTheShortcutLeftBehind() {
        let block = NoteBlock(text: "# Heading")
        let result = NoteBlockEditor.transform(doc(block), at: block.id, to: .heading1, text: "Heading")

        #expect(result.blocks[0].kind == .heading1)
        #expect(result.blocks[0].text == "Heading")
    }

    /// A rule holds no text and cannot take the caret, so one is inserted
    /// behind it. Without that, typing `---` strands the person.
    @Test func aRuleBringsAParagraphWithItForTheCaret() {
        let block = NoteBlock(text: "---")
        let result = NoteBlockEditor.transform(doc(block), at: block.id, to: .divider, text: "")

        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].kind == .divider)
        #expect(result.blocks[1].kind == .paragraph)
        #expect(result.focus == result.blocks[1].id)
    }

    // MARK: - Ordinals

    @Test func numberedRunsRestartAfterAnythingElse() {
        let blocks = doc(
            NoteBlock(kind: .numbered, text: "a"),
            NoteBlock(kind: .numbered, text: "b"),
            NoteBlock(kind: .paragraph, text: "break"),
            NoteBlock(kind: .numbered, text: "c")
        )
        let ordinals = NoteBlockEditor.ordinals(blocks)

        #expect(ordinals[blocks[0].id] == 1)
        #expect(ordinals[blocks[1].id] == 2)
        #expect(ordinals[blocks[2].id] == nil)
        #expect(ordinals[blocks[3].id] == 1)
    }

    // MARK: - Slash menu

    @Test func theSlashMenuOpensOnlyOnALeadingSlash() {
        #expect(NoteBlockEditor.slashQuery(in: "/") == "")
        #expect(NoteBlockEditor.slashQuery(in: "/head") == "head")
        #expect(NoteBlockEditor.slashQuery(in: "and/or") == nil)
    }

    /// A slash mid-sentence is a date or a path. A space ends the command.
    @Test func aSpaceClosesTheSlashMenu() {
        #expect(NoteBlockEditor.slashQuery(in: "/two words") == nil)
    }

    // MARK: - Link picker

    @Test func theLinkPickerOpensInsideUnclosedBrackets() {
        #expect(NoteBlockEditor.linkQuery(in: "see [[mar", caret: 9) == "mar")
        #expect(NoteBlockEditor.linkQuery(in: "see [[", caret: 6) == "")
    }

    @Test func aClosedLinkDoesNotReopenThePicker() {
        #expect(NoteBlockEditor.linkQuery(in: "see [[Marathon]] now", caret: 20) == nil)
    }

    @Test func textWithNoBracketsHasNoLinkQuery() {
        #expect(NoteBlockEditor.linkQuery(in: "just words", caret: 10) == nil)
    }

    @Test func completingALinkClosesTheBracketsSoItIsLiveAtOnce() {
        let block = NoteBlock(text: "training for [[mar")
        let result = NoteBlockEditor.completeLink(doc(block), at: block.id, with: "Marathon")

        #expect(result.blocks[0].text == "training for [[Marathon]]")
        #expect(NoteLinkScanner.links(in: result.blocks[0].text) == ["Marathon"])
    }

    @Test func completingALinkLeavesTheRestOfTheLineAlone() {
        let block = NoteBlock(text: "before [[a")
        let result = NoteBlockEditor.completeLink(doc(block), at: block.id, with: "Page")

        #expect(result.blocks[0].text.hasPrefix("before "))
    }

    // MARK: - Missing blocks

    @Test func anOperationOnABlockThatIsGoneChangesNothing() {
        let blocks = doc(NoteBlock(text: "here"))
        let stranger = UUID()

        #expect(NoteBlockEditor.split(blocks, at: stranger, before: "", after: "").handled == false)
        #expect(NoteBlockEditor.backspaceAtStart(blocks, at: stranger).handled == false)
        #expect(NoteBlockEditor.toggleCheck(blocks, at: stranger).handled == false)
        #expect(NoteBlockEditor.transform(blocks, at: stranger, to: .todo, text: "").handled == false)
    }

    // MARK: - The bar's pick

    @Test func changingTheKindKeepsTheWords() {
        let line = NoteBlock(text: "Buy oat milk")
        let result = NoteBlockEditor.changeKind(doc(line), at: line.id, to: .todo)

        #expect(result.handled)
        #expect(result.blocks[0].kind == .todo)
        #expect(result.blocks[0].text == "Buy oat milk")
        #expect(result.focus == line.id)
    }

    @Test func changingToARuleKeepsACaretBelow() {
        let line = NoteBlock(text: "Section")
        let result = NoteBlockEditor.changeKind(doc(line), at: line.id, to: .divider)

        #expect(result.blocks.map(\.kind) == [.divider, .paragraph])
        #expect(result.focus == result.blocks[1].id)
        #expect(result.blocks[1].text == "Section")
    }

    /// A sketch under the line, not instead of it: the words move down.
    @Test func changingToASketchKeepsTheWordsBelowIt() {
        let line = NoteBlock(text: "Buy milk and ring the dentist")
        let result = NoteBlockEditor.changeKind(doc(line), at: line.id, to: .sketch)

        #expect(result.blocks.map(\.kind) == [.sketch, .paragraph])
        #expect(result.blocks[1].text == "Buy milk and ring the dentist")
        #expect(result.focus == result.blocks[1].id)
    }

    @Test func changingToTheSameKindIsNotAnEdit() {
        let line = NoteBlock(kind: .todo, text: "Already a to-do")
        let result = NoteBlockEditor.changeKind(doc(line), at: line.id, to: .todo)

        #expect(!result.handled)
        #expect(result.blocks == doc(line))
    }

    @Test func changingTheKindOfAMissingBlockDoesNothing() {
        let line = NoteBlock(text: "Here")
        let result = NoteBlockEditor.changeKind(doc(line), at: UUID(), to: .todo)

        #expect(!result.handled)
        #expect(result.blocks == doc(line))
    }

    // MARK: - The title's Return

    @Test func aReturnTypedInTheTitleIsStrippedAndNoticed() {
        #expect(NoteBlockEditor.titleWithoutReturn("Weekend\n") == "Weekend")
        #expect(NoteBlockEditor.titleWithoutReturn("Week\nend reset") == "Weekend reset")
        #expect(NoteBlockEditor.titleWithoutReturn("Weekend reset") == nil)
        #expect(NoteBlockEditor.titleWithoutReturn("\n") == "")
    }

}

@Suite struct NoteSketchBlockTests {
    private func doc(_ blocks: NoteBlock...) -> [NoteBlock] { blocks }

    /// A sketch holds no text, so like a rule it has to leave somewhere to
    /// carry on typing or the person is stranded.
    @Test func insertingASketchLeavesAParagraphForTheCaret() {
        let block = NoteBlock(text: "/sketch")
        let result = NoteBlockEditor.transform(doc(block), at: block.id, to: .sketch, text: "")

        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].kind == .sketch)
        #expect(result.blocks[1].kind == .paragraph)
        #expect(result.focus == result.blocks[1].id)
    }

    @Test func aSketchIsNotTextual() {
        #expect(NoteBlockKind.sketch.isTextual == false)
        #expect(NoteBlockKind.sketch.continuesOnReturn == false)
        #expect(NoteBlockKind.sketch.markdownPrefix.isEmpty)
    }

    @Test func inkIsStoredOnTheBlockItWasDrawnIn() {
        let sketch = NoteBlock(kind: .sketch)
        let ink = Data([1, 2, 3, 4])
        let result = NoteBlockEditor.setDrawing(doc(sketch), at: sketch.id, drawing: ink)

        #expect(result.blocks[0].drawing == ink)
        #expect(result.blocks[0].isBlankSketch == false)
    }

    /// Empty ink is nil, so "has this been drawn in" has one answer.
    @Test func erasingASketchLeavesNilRatherThanEmptyInk() {
        let sketch = NoteBlock(kind: .sketch, drawing: Data([9]))
        let result = NoteBlockEditor.setDrawing(doc(sketch), at: sketch.id, drawing: Data())

        #expect(result.blocks[0].drawing == nil)
        #expect(result.blocks[0].isBlankSketch)
    }

    @Test func inkCannotBeStoredOnATextBlock() {
        let paragraph = NoteBlock(text: "words")
        #expect(NoteBlockEditor.setDrawing(doc(paragraph), at: paragraph.id, drawing: Data([1])).handled == false)
    }

    @Test func sketchHeightIsClampedToUsefulBounds() {
        let sketch = NoteBlock(kind: .sketch)
        let tall = NoteBlockEditor.setSketchHeight(doc(sketch), at: sketch.id, height: 5_000)
        let short = NoteBlockEditor.setSketchHeight(doc(sketch), at: sketch.id, height: 10)

        #expect(tall.blocks[0].resolvedSketchHeight == NoteBlock.maxSketchHeight)
        #expect(short.blocks[0].resolvedSketchHeight == NoteBlock.minSketchHeight)
    }

    @Test func anUndrawnSketchHasTheDefaultHeight() {
        #expect(NoteBlock(kind: .sketch).resolvedSketchHeight == NoteBlock.defaultSketchHeight)
    }

    /// Backspacing past a blank sketch removes it, the way it removes a rule.
    @Test func backspaceRemovesAnUntouchedSketch() {
        let sketch = NoteBlock(kind: .sketch)
        let below = NoteBlock(text: "after")
        let result = NoteBlockEditor.backspaceAtStart(doc(sketch, below), at: below.id)

        #expect(result.handled)
        #expect(result.blocks.count == 1)
        #expect(result.blocks[0].text == "after")
    }

    /// A drawing must not be deleted by a keystroke aimed at text. Losing ink
    /// to a held Backspace is unrecoverable.
    @Test func backspaceWillNotSwallowADrawnSketch() {
        let sketch = NoteBlock(kind: .sketch, drawing: Data([1, 2, 3]))
        let below = NoteBlock(text: "after")
        let result = NoteBlockEditor.backspaceAtStart(doc(sketch, below), at: below.id)

        #expect(result.handled == false)
        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].drawing != nil)
    }

    @Test func markdownSaysADrawingWasHereRatherThanDroppingIt() {
        let markdown = NoteBlockParser.markdown(doc(
            NoteBlock(text: "before"),
            NoteBlock(kind: .sketch, drawing: Data([1])),
            NoteBlock(text: "after")
        ))
        #expect(markdown.contains("[sketch]"))
    }

}
