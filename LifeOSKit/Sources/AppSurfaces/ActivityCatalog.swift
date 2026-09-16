import Foundation

/// One activity a person can record: what it is called, how it is drawn,
/// and how the recorder treats it. The name is both the display name and
/// the value stored on `WorkoutRecord.activityName` and on a session draft,
/// so it never changes once shipped.
public struct ActivityType: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case cardio = "Cardio"
        case strength = "Strength and Conditioning"
        case sports = "Racket and Ball Sports"
        case water = "Water"
        case outdoor = "Snow and Outdoor"
        case mindAndBody = "Mind and Body"
        case danceAndPlay = "Dance and Play"
        case other = "Other"
    }
    public let name: String
    public let group: Group
    /// An SF Symbol name.
    public let symbol: String
    /// `HKWorkoutActivityType.rawValue`. Kept as a number so this package
    /// stays free of HealthKit and keeps building for `swift test`.
    public let healthRawValue: UInt
    public let countsReps: Bool
    public let showsZones: Bool
    public let tracksDistance: Bool
    public var id: String { name }

    init(_ name: String, _ group: Group, _ symbol: String, _ healthRawValue: UInt,
         reps: Bool = false, zones: Bool = true, distance: Bool = false) {
        self.name = name; self.group = group; self.symbol = symbol; self.healthRawValue = healthRawValue
        countsReps = reps; showsZones = zones; tracksDistance = distance
    }
}

/// Every activity the Apple Watch Workout app offers, minus the three
/// HealthKit has deprecated and the two multisport containers.
public enum ActivityCatalog {
    public static let all: [ActivityType] = [
        // Cardio
        ActivityType("Walk", .cardio, "figure.walk", 52, distance: true),
        ActivityType("Run", .cardio, "figure.run", 37, distance: true),
        ActivityType("Cycle", .cardio, "figure.outdoor.cycle", 13, distance: true),
        ActivityType("Hiking", .cardio, "figure.hiking", 24, distance: true),
        ActivityType("Elliptical", .cardio, "figure.elliptical", 16),
        ActivityType("Rowing", .cardio, "figure.rower", 35, distance: true),
        ActivityType("Stair Climbing", .cardio, "figure.stair.stepper", 44),
        ActivityType("Stairs", .cardio, "figure.stairs", 68),
        ActivityType("Step Training", .cardio, "figure.step.training", 69),
        ActivityType("Jump Rope", .cardio, "figure.jumprope", 64),
        ActivityType("HIIT", .cardio, "figure.highintensity.intervaltraining", 63),
        ActivityType("Mixed Cardio", .cardio, "figure.mixed.cardio", 73),
        ActivityType("Cross Training", .cardio, "figure.cross.training", 11),
        ActivityType("Track and Field", .cardio, "figure.track.and.field", 49),
        ActivityType("Wheelchair Walk Pace", .cardio, "figure.roll", 70, distance: true),
        ActivityType("Wheelchair Run Pace", .cardio, "figure.roll.runningpace", 71, distance: true),
        ActivityType("Hand Cycling", .cardio, "figure.hand.cycling", 74, distance: true),
        // Strength and Conditioning
        ActivityType("Strength", .strength, "figure.strengthtraining.traditional", 50, reps: true),
        ActivityType("Functional Strength", .strength, "figure.strengthtraining.functional", 20, reps: true),
        ActivityType("Core Training", .strength, "figure.core.training", 59),
        ActivityType("Kickboxing", .strength, "figure.kickboxing", 65),
        ActivityType("Boxing", .strength, "figure.boxing", 8),
        ActivityType("Martial Arts", .strength, "figure.martial.arts", 28),
        ActivityType("Wrestling", .strength, "figure.wrestling", 56),
        ActivityType("Gymnastics", .strength, "figure.gymnastics", 22),
        ActivityType("Climbing", .strength, "figure.climbing", 9),
        ActivityType("Fencing", .strength, "figure.fencing", 18),
        ActivityType("Archery", .strength, "figure.archery", 2),
        // Racket and Ball Sports
        ActivityType("Badminton", .sports, "figure.badminton", 4),
        ActivityType("Tennis", .sports, "figure.tennis", 48),
        ActivityType("Table Tennis", .sports, "figure.table.tennis", 47),
        ActivityType("Pickleball", .sports, "figure.pickleball", 79),
        ActivityType("Squash", .sports, "figure.squash", 43),
        ActivityType("Racquetball", .sports, "figure.racquetball", 34),
        ActivityType("Basketball", .sports, "figure.basketball", 6),
        ActivityType("Soccer", .sports, "figure.soccer", 41),
        ActivityType("American Football", .sports, "figure.american.football", 1),
        ActivityType("Australian Football", .sports, "figure.australian.football", 3),
        ActivityType("Rugby", .sports, "figure.rugby", 36),
        ActivityType("Baseball", .sports, "figure.baseball", 5),
        ActivityType("Softball", .sports, "figure.softball", 42),
        ActivityType("Cricket", .sports, "figure.cricket", 10),
        ActivityType("Volleyball", .sports, "figure.volleyball", 51),
        ActivityType("Handball", .sports, "figure.handball", 23),
        ActivityType("Hockey", .sports, "figure.hockey", 25),
        ActivityType("Lacrosse", .sports, "figure.lacrosse", 27),
        ActivityType("Golf", .sports, "figure.golf", 21),
        ActivityType("Bowling", .sports, "figure.bowling", 7),
        ActivityType("Disc Sports", .sports, "figure.disc.sports", 75),
        ActivityType("Curling", .sports, "figure.curling", 12),
        // Water
        ActivityType("Swimming", .water, "figure.pool.swim", 46, distance: true),
        ActivityType("Water Fitness", .water, "figure.water.fitness", 53),
        ActivityType("Water Polo", .water, "figure.waterpolo", 54),
        ActivityType("Water Sports", .water, "figure.open.water.swim", 55),
        ActivityType("Surfing", .water, "figure.surfing", 45),
        ActivityType("Sailing", .water, "figure.sailing", 38),
        ActivityType("Paddle Sports", .water, "figure.outdoor.rowing", 31, distance: true),
        ActivityType("Underwater Diving", .water, "figure.open.water.swim", 84),
        // Snow and Outdoor
        ActivityType("Cross Country Skiing", .outdoor, "figure.skiing.crosscountry", 60, distance: true),
        ActivityType("Downhill Skiing", .outdoor, "figure.skiing.downhill", 61, distance: true),
        ActivityType("Snowboarding", .outdoor, "figure.snowboarding", 67, distance: true),
        ActivityType("Snow Sports", .outdoor, "figure.skiing.downhill", 40),
        ActivityType("Skating", .outdoor, "figure.skating", 39, distance: true),
        ActivityType("Fishing", .outdoor, "figure.fishing", 19),
        ActivityType("Hunting", .outdoor, "figure.hunting", 26),
        ActivityType("Equestrian Sports", .outdoor, "figure.equestrian.sports", 17),
        // Mind and Body
        ActivityType("Yoga", .mindAndBody, "figure.yoga", 57, zones: false),
        ActivityType("Pilates", .mindAndBody, "figure.pilates", 66, zones: false),
        ActivityType("Tai Chi", .mindAndBody, "figure.taichi", 72, zones: false),
        ActivityType("Barre", .mindAndBody, "figure.barre", 58),
        ActivityType("Flexibility", .mindAndBody, "figure.flexibility", 62, zones: false),
        ActivityType("Cooldown", .mindAndBody, "figure.cooldown", 80, zones: false),
        ActivityType("Preparation and Recovery", .mindAndBody, "figure.cooldown", 33, zones: false),
        ActivityType("Mind and Body", .mindAndBody, "figure.mind.and.body", 29, zones: false),
        // Dance and Play
        ActivityType("Cardio Dance", .danceAndPlay, "figure.dance", 77),
        ActivityType("Social Dance", .danceAndPlay, "figure.socialdance", 78),
        ActivityType("Play", .danceAndPlay, "figure.play", 32),
        ActivityType("Fitness Gaming", .danceAndPlay, "gamecontroller.fill", 76),
        // Other
        ActivityType("Other", .other, "figure.mixed.cardio", 3000),
    ]

    /// The six the app has always offered, in the order it offered them.
    public static let popular: [ActivityType] = ["Walk", "Run", "Cycle", "Strength", "Yoga", "Other"].compactMap { type(named: $0) }
    public static let other: ActivityType = all.last!

    private static let byName: [String: ActivityType] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    private static let byHealth: [UInt: ActivityType] = Dictionary(uniqueKeysWithValues: all.map { ($0.healthRawValue, $0) })

    /// Exact match first, so a stored name always resolves to itself; then
    /// case-insensitive, for anything typed.
    public static func type(named name: String) -> ActivityType? {
        if let exact = byName[name] { return exact }
        let folded = name.lowercased()
        guard !folded.isEmpty else { return nil }
        return all.first { $0.name.lowercased() == folded }
    }
    public static func type(healthRawValue value: UInt) -> ActivityType? { byHealth[value] }

    /// Name contains the trimmed query, case-insensitively, in catalog order.
    public static func search(_ query: String) -> [ActivityType] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(needle) }
    }
    /// Every group in declaration order, each holding its types in catalog order.
    public static func grouped() -> [(group: ActivityType.Group, types: [ActivityType])] {
        ActivityType.Group.allCases.map { group in (group, all.filter { $0.group == group }) }
    }
}
