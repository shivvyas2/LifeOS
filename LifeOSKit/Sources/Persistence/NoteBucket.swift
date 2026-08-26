import Foundation

/// The four shelves of the PARA method, in the order they are shown.
///
/// PARA sorts by actionability, not by subject: a note about running belongs
/// under a marathon *project* while the marathon is on, and under the *area*
/// that outlives it once the race is run. Encoding that as the top level of the
/// hierarchy is the whole point of the method, so it is an enum here rather
/// than four folders a user could rename into meaninglessness.
///
/// `research` is this app's name for PARA's "resources". The method's own word
/// is vaguer than what the shelf actually holds.
public enum NoteBucket: String, Codable, Sendable, CaseIterable, Identifiable {
    case projects, areas, research, archive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .projects: "Projects"
        case .areas:    "Areas"
        case .research: "Research"
        case .archive:  "Archive"
        }
    }

    /// Shown under the title on a shelf's own screen. Written to answer the
    /// only question a new PARA user actually has, which is "what goes here".
    public var blurb: String {
        switch self {
        case .projects:
            "Work with an end. A project has a finish line and a date you expect to cross it, and it leaves the shelf when you do."
        case .areas:
            "Standards you hold indefinitely. An area has no finish line, only a level you keep it at."
        case .research:
            "Things worth keeping that you are not acting on. Reading, references, notes toward something not yet started."
        case .archive:
            "Finished, dropped, or gone quiet. Nothing is deleted here, it is only out of the way."
        }
    }

    public var systemImage: String {
        switch self {
        case .projects: "target"
        case .areas:    "circle.grid.2x2"
        case .research: "books.vertical"
        case .archive:  "archivebox"
        }
    }

    /// The three shelves a note can be filed into by hand. Archive is a state a
    /// note is put into, never a place it is created, so the "move to" pickers
    /// and the new-folder button read this rather than `allCases`.
    public static var filing: [NoteBucket] { [.projects, .areas, .research] }
}
