import Testing
@testable import Sectors

struct WorkoutLibraryFilterTests {
    private func video(_ id: String, title: String = "A workout", split: String = "pull", intensity: Int = 2,
                       minutes: Int = 30, goal: [String] = ["strength"], equipment: [String] = ["dumbbells"],
                       channel: String = "A Channel", muscles: [String] = []) -> LibraryVideo {
        LibraryVideo(id: id, title: title, split: split, intensity: intensity, durationMinutes: minutes,
                     goal: goal, equipment: equipment, channel: channel, muscles: muscles)
    }
    private let plan = TrainingPlan(split: "pull", minutes: 30, maxIntensity: 2, reason: "Pull day.")

    @Test func widensToAnyLengthThenAnySplit() {
        let long = video("long", split: "pull", minutes: 75)
        let other = video("push", split: "push", minutes: 30)
        // Nothing in the plan's split at the plan's length: the length gives first.
        let widenedLength = WorkoutLibraryFilter.apply(videos: [long, other], plan: plan, goal: "strength",
                                                       split: nil, band: nil, equipment: [])
        #expect(widenedLength.rows.map(\.id) == ["long"])
        #expect(widenedLength.note == "Widened to any length.")
        // Nothing in the plan's split at all: the split gives next.
        let widenedSplit = WorkoutLibraryFilter.apply(videos: [other], plan: plan, goal: "strength",
                                                      split: nil, band: nil, equipment: [])
        #expect(widenedSplit.rows.map(\.id) == ["push"])
        #expect(widenedSplit.note == "Widened to any split for your goal.")
        // A full list widens nothing and says nothing.
        let exact = WorkoutLibraryFilter.apply(videos: [video("fits"), other], plan: plan, goal: "strength",
                                               split: nil, band: nil, equipment: [])
        #expect(exact.rows.map(\.id) == ["fits"])
        #expect(exact.note == nil)
    }

    @Test func keepsIntensityCapWhileWidening() {
        // The only rows in any split are above the plan's cap: widening reaches
        // no further than the cap, and the list stays honestly empty.
        let hard = video("hard", split: "push", intensity: 3, minutes: 30)
        let hardPull = video("hardpull", split: "pull", intensity: 3, minutes: 30)
        let result = WorkoutLibraryFilter.apply(videos: [hard, hardPull], plan: plan, goal: "strength",
                                                split: nil, band: nil, equipment: [])
        #expect(result.rows.isEmpty)
        #expect(result.note == nil)
        // The same catalog with one row at the cap returns only that row.
        let easy = video("easy", split: "push", intensity: 1, minutes: 30)
        let widened = WorkoutLibraryFilter.apply(videos: [hard, hardPull, easy], plan: plan, goal: "strength",
                                                 split: nil, band: nil, equipment: [])
        #expect(widened.rows.map(\.id) == ["easy"])
        #expect(widened.note == "Widened to any split for your goal.")
    }

    @Test func ordersByClosenessThenTitle() {
        let rows = [video("far", title: "Zulu", minutes: 40), video("near", title: "Mike", minutes: 32),
                    video("tie", title: "Alpha", minutes: 40)]
        let result = WorkoutLibraryFilter.apply(videos: rows, plan: plan, goal: "strength",
                                                split: nil, band: nil, equipment: [])
        #expect(result.rows.map(\.id) == ["near", "tie", "far"])
    }

    @Test func explicitSplitChipIsNotWidenedAway() {
        let legs = video("legs", split: "legs", minutes: 75)
        let pull = video("pull", split: "pull", minutes: 30)
        // The chip says legs and only a 75 minute legs row exists: the length
        // widens, the split does not.
        let chosen = WorkoutLibraryFilter.apply(videos: [legs, pull], plan: plan, goal: "strength",
                                                split: "legs", band: nil, equipment: [])
        #expect(chosen.rows.map(\.id) == ["legs"])
        #expect(chosen.note == "Widened to any length.")
        // Nothing at all in the chosen split: the list stays empty rather than
        // answering a chip the person tapped with some other split's rows.
        let empty = WorkoutLibraryFilter.apply(videos: [pull], plan: plan, goal: "strength",
                                               split: "legs", band: nil, equipment: [])
        #expect(empty.rows.isEmpty)
        #expect(empty.note == nil)
    }

    @Test func equipmentAndBandNarrowWithoutWidening() {
        let bands = video("bands", minutes: 15, equipment: ["bands"])
        let dumbbells = video("dumbbells", minutes: 15, equipment: ["dumbbells"])
        let result = WorkoutLibraryFilter.apply(videos: [bands, dumbbells], plan: plan, goal: "strength",
                                                split: nil, band: .under20, equipment: ["bands"])
        #expect(result.rows.map(\.id) == ["bands"])
    }

    @Test func searchMatchesTitleChannelOrMuscle() {
        let byTitle = video("byTitle", title: "Back and Biceps Burner")
        let byChannel = video("byChannel", title: "Something Else", channel: "Athlean Extra")
        let byMuscle = video("byMuscle", title: "Nothing Related", channel: "Other", muscles: ["Hamstrings"])
        let miss = video("miss", title: "Nope", channel: "Nada", muscles: ["Quads"])
        let result = WorkoutLibraryFilter.apply(videos: [byTitle, byChannel, byMuscle, miss], plan: plan,
                                                goal: "strength", split: nil, band: nil, equipment: [],
                                                query: "  BICEPS ")
        #expect(result.rows.map(\.id) == ["byTitle"])

        let channelResult = WorkoutLibraryFilter.apply(videos: [byTitle, byChannel, byMuscle, miss], plan: plan,
                                                        goal: "strength", split: nil, band: nil, equipment: [],
                                                        query: "athlean")
        #expect(channelResult.rows.map(\.id) == ["byChannel"])

        let muscleResult = WorkoutLibraryFilter.apply(videos: [byTitle, byChannel, byMuscle, miss], plan: plan,
                                                       goal: "strength", split: nil, band: nil, equipment: [],
                                                       query: "hamstrings")
        #expect(muscleResult.rows.map(\.id) == ["byMuscle"])
    }

    @Test func searchSurvivesWidening() {
        // Only a long, off-plan-length pull video matches the query: widening
        // for length must still keep the query narrowing it to just that row.
        let matchLong = video("matchLong", title: "Deadlift Deep Dive", split: "pull", minutes: 75)
        let noMatchAtPlanLength = video("noMatch", title: "Row City", split: "pull", minutes: 30)
        let result = WorkoutLibraryFilter.apply(videos: [matchLong, noMatchAtPlanLength], plan: plan,
                                                goal: "strength", split: nil, band: nil, equipment: [],
                                                query: "deadlift")
        #expect(result.rows.map(\.id) == ["matchLong"])
    }

    @Test func savedListIgnoresThePlanButNotTheQuery() {
        // Off the plan's split, over its intensity cap, far past its length,
        // and kit the person did not pick: a saved row shows anyway.
        let offPlan = video("offPlan", title: "Push Power", split: "push", intensity: 3,
                            minutes: 75, equipment: ["barbell"])
        let onPlan = video("onPlan", title: "Pull Day", split: "pull", minutes: 30)
        #expect(WorkoutLibraryFilter.saved(videos: [offPlan, onPlan]).map(\.id) == ["offPlan", "onPlan"])
        // The caller's order is the order, so a sort by when each was saved
        // survives the filter.
        #expect(WorkoutLibraryFilter.saved(videos: [onPlan, offPlan]).map(\.id) == ["onPlan", "offPlan"])
        // A search still narrows the saved list, trimmed and case-folded the
        // same way the plan's own filter does it.
        #expect(WorkoutLibraryFilter.saved(videos: [offPlan, onPlan], query: "  PUSH ").map(\.id) == ["offPlan"])
        #expect(WorkoutLibraryFilter.saved(videos: [offPlan, onPlan], query: "nothing").isEmpty)
    }

    @Test func emptyQueryChangesNothing() {
        let rows = [video("a", title: "Alpha"), video("b", title: "Bravo")]
        let withoutQuery = WorkoutLibraryFilter.apply(videos: rows, plan: plan, goal: "strength",
                                                       split: nil, band: nil, equipment: [])
        let withEmptyQuery = WorkoutLibraryFilter.apply(videos: rows, plan: plan, goal: "strength",
                                                         split: nil, band: nil, equipment: [], query: "   ")
        #expect(withoutQuery.rows.map(\.id) == withEmptyQuery.rows.map(\.id))
        #expect(withoutQuery.note == withEmptyQuery.note)
    }
}
