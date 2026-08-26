import Foundation

/// The pastel a folder's dot and a note's card are painted in.
///
/// Colour lives in the design system, so this is only the name. Persistence
/// must not import SwiftUI: this package builds for macOS so `swift test` runs
/// without a simulator, and the moment a `@Model` holds a `Color` that stops
/// being true.
///
/// Eight, chosen so a sidebar of a dozen folders still reads as a set rather
/// than a rainbow. `next(after:)` hands them out in order for auto-assignment.
public enum NoteAccent: String, Codable, Sendable, CaseIterable, Identifiable {
    case sage, sand, sky, lilac, clay, rose, moss, slate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sage:  "Sage"
        case .sand:  "Sand"
        case .sky:   "Sky"
        case .lilac: "Lilac"
        case .clay:  "Clay"
        case .rose:  "Rose"
        case .moss:  "Moss"
        case .slate: "Slate"
        }
    }

    /// The accent a new folder or note takes, given how many already exist.
    /// Cycling beats random: two folders made a second apart never collide.
    public static func next(after count: Int) -> NoteAccent {
        let all = allCases
        return all[((count % all.count) + all.count) % all.count]
    }

    /// Stable per-title accent, for rows that have no stored colour of their
    /// own. Hashing the title rather than using `hashValue` because Swift's
    /// hash is seeded per process and the colour would change on every launch.
    public static func derived(from title: String) -> NoteAccent {
        let sum = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return allCases[sum % allCases.count]
    }
}
