import Testing
@testable import AppSurfaces

struct ActivityCatalogTests {
    @Test func catalogHasEveryCurrentTypeOnce() {
        let all = ActivityCatalog.all
        #expect(all.count == 79)
        #expect(Set(all.map(\.name)).count == 79)
        #expect(Set(all.map(\.healthRawValue)).count == 79)
        // dance, danceInspiredTraining, mixedMetabolicCardioTraining, swimBikeRun, transition
        for excluded: UInt in [14, 15, 30, 82, 83] {
            #expect(ActivityCatalog.type(healthRawValue: excluded) == nil)
        }
        #expect(ActivityCatalog.type(healthRawValue: 3000)?.name == "Other")
    }

    @Test func lookupByNameIsExactThenCaseInsensitive() {
        #expect(ActivityCatalog.type(named: "Badminton")?.healthRawValue == 4)
        #expect(ActivityCatalog.type(named: "badminton")?.name == "Badminton")
        #expect(ActivityCatalog.type(named: "Nonsense") == nil)
        #expect(ActivityCatalog.type(named: "") == nil)
    }

    @Test func lookupByHealthValueRoundTripsEveryEntry() {
        for type in ActivityCatalog.all {
            #expect(ActivityCatalog.type(healthRawValue: type.healthRawValue) == type)
        }
    }

    @Test func popularIsTheOriginalSixInOrder() {
        #expect(ActivityCatalog.popular.map(\.name) == ["Walk", "Run", "Cycle", "Strength", "Yoga", "Other"])
        #expect(ActivityCatalog.other.name == "Other")
    }

    @Test func searchMatchesByNameAndKeepsCatalogOrder() {
        #expect(ActivityCatalog.search("bad").map(\.name) == ["Badminton"])
        #expect(ActivityCatalog.search("  Ski ").map(\.name) == ["Cross Country Skiing", "Downhill Skiing"])
        #expect(ActivityCatalog.search("").count == 79)
        #expect(ActivityCatalog.search("zzz").isEmpty)
    }

    @Test func groupedCoversEveryEntryOnceInCatalogOrder() {
        let grouped = ActivityCatalog.grouped()
        #expect(grouped.map(\.group) == ActivityType.Group.allCases)
        #expect(grouped.flatMap(\.types).count == 79)
        let sports = grouped.first { $0.group == .sports }?.types.map(\.name) ?? []
        #expect(sports.first == "Badminton")
        #expect(sports.contains("Pickleball") && sports.contains("Table Tennis"))
        for entry in grouped { #expect(entry.types == ActivityCatalog.all.filter { $0.group == entry.group }) }
    }

    @Test func flagsHoldForTheNamedEntries() {
        #expect(ActivityCatalog.all.filter(\.countsReps).map(\.name) == ["Strength", "Functional Strength"])
        let noZones = ActivityCatalog.all.filter { !$0.showsZones }.map(\.name)
        #expect(Set(noZones) == ["Yoga", "Pilates", "Tai Chi", "Flexibility", "Cooldown", "Preparation and Recovery", "Mind and Body"])
        let distance = ActivityCatalog.all.filter(\.tracksDistance).map(\.name)
        #expect(Set(distance) == ["Walk", "Run", "Cycle", "Hiking", "Wheelchair Walk Pace", "Wheelchair Run Pace", "Hand Cycling",
                                  "Swimming", "Rowing", "Paddle Sports", "Cross Country Skiing", "Downhill Skiing", "Snowboarding", "Skating"])
        #expect(ActivityCatalog.type(named: "Badminton")?.symbol == "figure.badminton")
    }
}
