import Testing
@testable import DesignSystem

@Suite struct NotesHeadlineTests {
    @Test func countWording() {
        #expect(NotesHeadline.eyebrow(count: 0) == "Notes · No pages")
        #expect(NotesHeadline.eyebrow(count: 1) == "Notes · 1 page")
        #expect(NotesHeadline.eyebrow(count: 24) == "Notes · 24 pages")
    }

    @Test func scopedWording() {
        #expect(NotesHeadline.eyebrow(.inbox, count: 0) == "Notes · Nothing in Inbox")
        #expect(NotesHeadline.eyebrow(.inbox, count: 1) == "Notes · 1 in Inbox")
        #expect(NotesHeadline.eyebrow(.inbox, count: 3) == "Notes · 3 in Inbox")
        #expect(NotesHeadline.eyebrow(.all, count: 24) == "Notes · 24 pages")
        #expect(NotesHeadline.eyebrow(.pages, count: 1) == "Notes · 1 page")
        #expect(NotesHeadline.eyebrow(.todos, count: 0) == "Notes · No to-dos")
        #expect(NotesHeadline.eyebrow(.todos, count: 1) == "Notes · 1 to-do")
        #expect(NotesHeadline.eyebrow(.todos, count: 5) == "Notes · 5 to-dos")
        #expect(NotesHeadline.eyebrow(.favorites, count: 0) == "Notes · No favourites")
        #expect(NotesHeadline.eyebrow(.favorites, count: 1) == "Notes · 1 favourite")
        #expect(NotesHeadline.eyebrow(.favorites, count: 2) == "Notes · 2 favourites")
    }
}
