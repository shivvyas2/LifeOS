import Testing
import Foundation
import Persistence
@testable import Integrations

@Suite struct NoteWireFormatTests {

    private func makeRow(
        drawing: Data? = nil,
        entryDate: Date? = nil,
        deletedAt: Date? = nil,
        blocks: [NoteBlock] = [NoteBlock(kind: .todo, text: "Long run", isChecked: true, indent: 1)]
    ) -> NoteDocumentRow {
        NoteDocumentRow(
            id: UUID(), title: "Marathon", icon: "\u{1F3C3}", kind: "note",
            bucket: "projects", accent: "clay", folderID: UUID(),
            blocks: blocks, drawing: drawing,
            entryDate: entryDate, dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            status: "inProgress", sortOrder: 3, isFavorite: true,
            openedAt: Date(timeIntervalSince1970: 1_700_000_100),
            archivedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            deletedAt: deletedAt
        )
    }

    /// The whole point of the row type: what goes up must come back as the same
    /// page, or a second device shows something the first one never wrote.
    @Test func aDocumentSurvivesTheRoundTrip() throws {
        let original = makeRow()
        let decoded = try #require(NoteDocumentRow(json: original.payload()))

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.icon == original.icon)
        #expect(decoded.bucket == original.bucket)
        #expect(decoded.accent == original.accent)
        #expect(decoded.folderID == original.folderID)
        #expect(decoded.status == original.status)
        #expect(decoded.sortOrder == original.sortOrder)
        #expect(decoded.isFavorite == original.isFavorite)
    }

    @Test func blocksKeepTheirKindTextTickAndIndent() throws {
        let original = makeRow()
        let decoded = try #require(NoteDocumentRow(json: original.payload()))

        #expect(decoded.blocks.count == 1)
        #expect(decoded.blocks[0].kind == .todo)
        #expect(decoded.blocks[0].text == "Long run")
        #expect(decoded.blocks[0].isChecked)
        #expect(decoded.blocks[0].indent == 1)
        // Block identity has to survive too, or every pull reshuffles the
        // editor's ForEach and the caret jumps.
        #expect(decoded.blocks[0].id == original.blocks[0].id)
    }

    /// Blocks go over as real JSON, not as an encoded string, so Postgres can
    /// refuse a malformed document at write time.
    @Test func blocksAreSentAsJsonNotAsAString() {
        let payload = makeRow().payload()

        #expect(payload["blocks"] is [[String: Any]])
    }

    @Test func aRoundTrippedTimestampKeepsItsInstant() throws {
        let original = makeRow()
        let decoded = try #require(NoteDocumentRow(json: original.payload()))

        #expect(abs(decoded.updatedAt.timeIntervalSince(original.updatedAt)) < 0.001)
        #expect(abs(decoded.createdAt.timeIntervalSince(original.createdAt)) < 0.001)
    }

    /// A journal entry's date is a local midnight. Sending it as UTC would file
    /// every entry written east of Greenwich under the previous day.
    @Test func aJournalDateComesBackOnTheSameCalendarDay() throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try #require(NoteDocumentRow(json: makeRow(entryDate: day).payload()))

        let returned = try #require(decoded.entryDate)
        #expect(calendar.isDate(returned, inSameDayAs: day))
    }

    @Test func nullColumnsComeBackAsNil() throws {
        let row = NoteDocumentRow(
            id: UUID(), title: "", icon: "", kind: "note", bucket: "projects",
            accent: "sage", folderID: nil, blocks: NoteBlock.blank, drawing: nil,
            entryDate: nil, dueDate: nil, status: "todo", sortOrder: 0,
            isFavorite: false, openedAt: nil, archivedAt: nil,
            createdAt: .now, updatedAt: .now, deletedAt: nil
        )
        let decoded = try #require(NoteDocumentRow(json: row.payload()))

        #expect(decoded.folderID == nil)
        #expect(decoded.entryDate == nil)
        #expect(decoded.dueDate == nil)
        #expect(decoded.drawing == nil)
        #expect(decoded.deletedAt == nil)
    }

    @Test func inkIsCarriedAsBase64AndComesBackAsTheSameBytes() throws {
        let ink = Data((0..<512).map { UInt8($0 % 251) })
        let decoded = try #require(NoteDocumentRow(json: makeRow(drawing: ink).payload()))

        #expect(decoded.drawing == ink)
    }

    /// One pathological page must not stall every other page's sync behind it.
    /// The text still goes; the ink stays on the device that made it.
    @Test func oversizedInkIsLeftBehindRatherThanFailingTheWholePush() {
        let huge = Data(repeating: 7, count: NoteDocumentRow.maxDrawingBytes + 1)
        let payload = makeRow(drawing: huge).payload()

        #expect(payload["drawing"] is NSNull)
        #expect(payload["title"] as? String == "Marathon")
    }

    @Test func aTombstoneCarriesItsDeletionTime() throws {
        let deleted = Date(timeIntervalSince1970: 1_700_000_300)
        let decoded = try #require(NoteDocumentRow(json: makeRow(deletedAt: deleted).payload()))

        #expect(abs(try #require(decoded.deletedAt).timeIntervalSince(deleted)) < 0.001)
    }

    /// The server owns `user_id` through the column default, so RLS decides
    /// ownership from the token. A client asserting it would be refused, and
    /// the failure would read like a permissions bug.
    @Test func theClientNeverClaimsOwnership() {
        #expect(makeRow().payload()["user_id"] == nil)
        #expect(NoteFolderRow(
            id: UUID(), name: "Training", icon: "", bucket: "projects", accent: "sage",
            parentID: nil, sortOrder: 0, createdAt: .now, updatedAt: .now, deletedAt: nil
        ).payload()["user_id"] == nil)
    }

    @Test func aFolderSurvivesTheRoundTrip() throws {
        let parent = UUID()
        let original = NoteFolderRow(
            id: UUID(), name: "Training", icon: "\u{1F3AF}", bucket: "areas",
            accent: "moss", parentID: parent, sortOrder: 4,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            deletedAt: nil
        )
        let decoded = try #require(NoteFolderRow(json: original.payload()))

        #expect(decoded == original)
    }

    @Test func aRowWithNoIdOrTimestampIsRefusedRatherThanGuessedAt() {
        #expect(NoteDocumentRow(json: ["title": "orphan"]) == nil)
        #expect(NoteFolderRow(json: ["name": "orphan"]) == nil)
    }

    /// A block kind this build does not know about is dropped rather than
    /// defaulted to a paragraph: an old client silently rewriting a new block
    /// type into text would lose it for every device on the next push.
    @Test func unknownBlockKindsAreDroppedNotGuessed() {
        let blocks = NoteDocumentRow.blocks(from: [
            ["id": UUID().uuidString, "kind": "hologram", "text": "future"],
            ["id": UUID().uuidString, "kind": "paragraph", "text": "known"],
        ])

        #expect(blocks.count == 1)
        #expect(blocks[0].text == "known")
    }

    @Test func aDocumentWithNoBlocksStillHasSomewhereToType() {
        #expect(NoteDocumentRow.blocks(from: []).count == 1)
        #expect(NoteDocumentRow.blocks(from: nil).count == 1)
    }
}
