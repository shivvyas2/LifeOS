/// The Notes masthead eyebrow, so "1 pages" never ships.
public enum NotesHeadline {
    public static func eyebrow(count: Int) -> String {
        switch count {
        case 0: "Notes · No pages"
        case 1: "Notes · 1 page"
        default: "Notes · \(count) pages"
        }
    }
}
