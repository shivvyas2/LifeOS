import Testing
@testable import DesignSystem

@Suite struct NotesHeadlineTests {
    @Test func countWording() {
        #expect(NotesHeadline.eyebrow(count: 0) == "Notes · No pages")
        #expect(NotesHeadline.eyebrow(count: 1) == "Notes · 1 page")
        #expect(NotesHeadline.eyebrow(count: 24) == "Notes · 24 pages")
    }
}
