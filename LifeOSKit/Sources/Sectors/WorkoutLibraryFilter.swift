import Foundation

/// The three length bands the library filters by. Bounds are inclusive at the
/// bottom and exclusive at the top so every minute count lands in exactly one.
public enum DurationBand: String, CaseIterable, Sendable {
    case under20, from20to40, over40

    public func contains(_ minutes: Int) -> Bool {
        switch self {
        case .under20: minutes < 20
        case .from20to40: (20...40).contains(minutes)
        case .over40: minutes > 40
        }
    }
}

/// A catalog row, reduced to the fields the filter reads. The view model maps
/// its cached `CatalogVideo` rows to these and back by id, so the rule the
/// screen renders is a pure function with tests rather than a method on a
/// SwiftData model no test target can reach.
public struct LibraryVideo: Equatable, Sendable {
    public let id: String
    public let title: String
    public let split: String
    public let intensity: Int
    public let durationMinutes: Int
    public let goal: [String]
    public let equipment: [String]
    public let channel: String
    public let muscles: [String]

    public init(id: String, title: String, split: String, intensity: Int,
                durationMinutes: Int, goal: [String], equipment: [String],
                channel: String = "", muscles: [String] = []) {
        self.id = id; self.title = title; self.split = split; self.intensity = intensity
        self.durationMinutes = durationMinutes; self.goal = goal; self.equipment = equipment
        self.channel = channel; self.muscles = muscles
    }
}

/// The plan first: its split, its intensity cap, its length give or take
/// fifteen minutes. An empty result widens one step at a time and says which
/// step it took, so a short list is never a mystery.
public enum WorkoutLibraryFilter {
    public static func apply(videos: [LibraryVideo], plan: TrainingPlan, goal: String?, split: String?,
                             band: DurationBand?, equipment: Set<String>, query: String = "") -> (rows: [LibraryVideo], note: String?) {
        let chosenSplit = split ?? plan.split
        // A search the person typed narrows the catalog before anything
        // else, and stays narrowed through every widening step below: the
        // plan's filters are preferences to relax, the query is not.
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // The intensity cap and the equipment the person owns are never
        // widened away: a battery ceiling and a kit list are facts, not
        // preferences to relax when the list comes back short.
        let base = videos.filter { video in
            video.intensity <= plan.maxIntensity
                && (equipment.isEmpty || !Set(video.equipment).isDisjoint(with: equipment))
                && (normalizedQuery.isEmpty || matches(video, query: normalizedQuery))
        }
        func inBand(_ video: LibraryVideo) -> Bool {
            if let band { return band.contains(video.durationMinutes) }
            return abs(video.durationMinutes - plan.minutes) <= 15
        }

        var note: String?
        var result = base.filter { $0.split == chosenSplit && inBand($0) }
        if result.isEmpty {
            result = base.filter { $0.split == chosenSplit }
            if !result.isEmpty { note = "Widened to any length." }
        }
        // Only when the split is the plan's own. A chip the person tapped is
        // an instruction, and answering it with another split while the chip
        // still reads selected would be the screen contradicting itself.
        if result.isEmpty, split == nil {
            result = base.filter { video in goal.map { video.goal.contains($0) } ?? true }
            if !result.isEmpty { note = "Widened to any split for your goal." }
        }

        let rows = result.sorted {
            let left = abs($0.durationMinutes - plan.minutes), right = abs($1.durationMinutes - plan.minutes)
            return left == right ? $0.title < $1.title : left < right
        }
        return (rows, note)
    }

    private static func matches(_ video: LibraryVideo, query: String) -> Bool {
        video.title.lowercased().contains(query)
            || video.channel.lowercased().contains(query)
            || video.muscles.contains { $0.lowercased().contains(query) }
    }
}
