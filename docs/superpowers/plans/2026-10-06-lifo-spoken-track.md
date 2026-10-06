# LIFO spoken track Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** LIFO's voice explains the screen instead of summarising it once: the model writes a spoken passage per section, each card reveals the moment its passage starts to play, passages are capped per answer and budgeted per month, and when the month's allowance is spent the device voice carries the narration.

**Architecture:** `SpokenReply` becomes `SpokenTrack` in `Insights`: a tested parser that splits a streamed reply into segments of `(spoken passage, shown sections)`, knows how many rendered blocks each segment carries, and trims passages to a character budget. `VoiceBudget` in `Insights` is a tested per-account monthly counter. In the app, `VoicePlayer` plays a queue of audio segments and reports each start; `DeviceVoiceClient` renders text to WAV with `AVSpeechSynthesizer` so the same player carries the fallback; `CoachViewModel` fetches passages in order, debits the budget, and exposes `revealedBlocks`; `CoachResponseView` draws only the revealed blocks; Settings shows the month's usage. A DEBUG hook lets the `coach-voice` preview narrate a canned reply through a stub synthesiser so the staged reveal can be captured.

**Tech Stack:** SwiftUI, AVFoundation (`AVAudioPlayer`, `AVSpeechSynthesizer`), Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl`.

**Spec:** `docs/superpowers/specs/2026-10-06-lifo-spoken-track-design.md`. PR 3 of the order in `docs/superpowers/specs/2026-10-06-editorial-calendar-find-ask-widget-design.md` section 6, after `feat/editorial-coach` (PR #22).

## Global Constraints

- One completion per turn, one debit, one set of figures: the track is parsed out of the single streamed reply. No second model call is ever made for the voice.
- Nothing may ever speak a table: `CoachResponse.spokenText` is deleted and nothing replaces it. The fallback for a reply with no `SAY:` line stays the first plain paragraph, once.
- The written sections follow `CoachPresentation.instruction` unchanged; `spokenTrackInstruction` replaces `spokenLineInstruction` and is added only when `voiceAvailable` is true, exactly where the old line was added. Both tiers get the same addition; `supabase/functions` is not touched.
- The budget is `VoiceBudget.monthlyAllowance = 30_000` characters per account per month, keyed `voice.characters.<yyyy-MM>` in `UserDefaults.currentAccount`. The per-answer cap is 700 characters. `ElevenLabsVoiceClient.maxCharacters` (1,200) remains the per-request ceiling for one passage.
- Paper and ink as before; the only new on-screen text is a quiet line and a Settings usage line, both in `LifeOSType` steps. No new colours.
- `LifeOSKit` builds for macOS too (`swift test` runs there): `SpokenTrack` and `VoiceBudget` use Foundation only. `AVSpeechSynthesizer` and `AVAudioPlayer` code stays in the app target.
- Typography: `scripts/check-typography.sh` reports nothing new versus the base commit.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution of any kind.
- Work happens in the existing worktree `.claude/worktrees/lifo-spoken-track` on branch `feat/lifo-spoken-track`, cut from `origin/feat/editorial-coach` at `4cb2518`. `Config/Secrets.xcconfig` is already copied in. The PR targets `feat/editorial-coach` until #22 merges, then `main`.
- Only one simulator remains on this Mac, `iPhone 17`, id `780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4`, shared with other sessions. Capture after a fresh launch and do not erase it.

## Review Focus

1. A reply whose later `SAY:` line is still streaming must not start a half passage: `SpokenTrackTests.aSecondPassageIsPendingUntilItsNewline` in Task 1.
2. A section with no passage of its own reveals with the passage before it, so the reveal count after segment `i` includes it: `SpokenTrackTests.aSectionWithoutAPassageMergesIntoThePrevious` and `revealedBlocksAccumulate` in Task 1.
3. The cap never drops the opening and cuts at a sentence boundary, never mid-number: `SpokenTrackTests.cappingKeepsTheOpeningAndCutsAtSentences` in Task 1.
4. A new month resets the budget and the allowance is read from the constant: `VoiceBudgetTests.aNewMonthStartsFresh` in Task 2.
5. When a passage's fetch fails, its blocks still appear (with the next start, or at once if it was last), and stopping the voice reveals everything: no unit test reaches `VoicePlayer`, so the `coach-voice --track=3 --fail=2` capture in Task 8 shows all blocks on screen after the stub refuses segment 2.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/Insights/SpokenTrack.swift` (renamed from `SpokenReply.swift`) | The track parser, cap and reveal counts |
| `LifeOSKit/Tests/InsightsTests/SpokenTrackTests.swift` (renamed from `SpokenReplyTests.swift`) | Its tests |
| `LifeOSKit/Sources/Insights/CoachResponse.swift` | `spokenTrackInstruction`; `spokenText` deleted |
| `LifeOSKit/Sources/Insights/VoiceBudget.swift` (new) | Monthly character counter |
| `LifeOSKit/Tests/InsightsTests/VoiceBudgetTests.swift` (new) | Its tests |
| `LIfeOS/Features/Coach/Model/ElevenLabsVoiceClient.swift` | `VoicePlayer` plays a queue and reports starts |
| `LIfeOS/Features/Coach/Model/DeviceVoiceClient.swift` (new) | `AVSpeechSynthesizer` to WAV data |
| `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift` | Narration, budget, reveal state, preview hook |
| `LIfeOS/Features/Coach/View/CoachResponseView.swift` | `revealed:` parameter |
| `LIfeOS/Features/Coach/View/LifoCoachScreen.swift` | Passes `revealedBlocks`; the quiet notice |
| `LIfeOS/Features/Settings/View/SettingsScreen.swift` | Usage line under the voice picker |
| `LIfeOS/Features/Coach/View/CoachDesignPreview.swift` | `--track=3`, `--fail=N`, `--budget-spent` |

---

### Task 0: Worktree and the typography baseline

- [ ] **Step 1: Confirm the worktree**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/lifo-spoken-track
git status --short && git log --oneline -1 && ls Config/Secrets.xcconfig
```

Expected: a clean tree at `4cb2518 fix(coach): Return sends, ink caret, and an 800pt cap on the assistant` (or a later commit of `feat/editorial-coach`; then `git fetch origin && git rebase origin/feat/editorial-coach` first), and the secrets file present.

- [ ] **Step 2: Record the typography baseline**

```bash
scripts/check-typography.sh > /tmp/typo-track-base.txt 2>&1; echo "baseline lines: $(wc -l < /tmp/typo-track-base.txt)"
```

---

### Task 1: `SpokenTrack`

**Files:**
- Rename: `LifeOSKit/Sources/Insights/SpokenReply.swift` to `LifeOSKit/Sources/Insights/SpokenTrack.swift`
- Rename: `LifeOSKit/Tests/InsightsTests/SpokenReplyTests.swift` to `LifeOSKit/Tests/InsightsTests/SpokenTrackTests.swift`
- Modify: `LifeOSKit/Sources/Insights/CoachResponse.swift` (delete `spokenText`; replace `spokenLineInstruction` with `spokenTrackInstruction`)

**Interfaces:**
- Consumes: `ResponseStyle.clean(_:)`, `CoachResponse(_:).blocks`.
- Produces: `public struct SpokenTrack { static let prefix = "SAY:"; struct Segment { spoken: String?; shown: String }; segments: [Segment]; isOpeningPending: Bool; opening: String?; shownText: String; blockCount: Int; init(parsing:); func capped(to: Int = 700) -> SpokenTrack; func revealedBlocks(throughSegment: Int) -> Int }` and `CoachPresentation.spokenTrackInstruction`. Task 5 consumes all of it. `SpokenReply` no longer exists; `CoachViewModel` stops compiling until Task 5, which is expected.

- [ ] **Step 1: Rename both files**

```bash
git mv LifeOSKit/Sources/Insights/SpokenReply.swift LifeOSKit/Sources/Insights/SpokenTrack.swift
git mv LifeOSKit/Tests/InsightsTests/SpokenReplyTests.swift LifeOSKit/Tests/InsightsTests/SpokenTrackTests.swift
```

- [ ] **Step 2: Write the failing tests** (the whole test file)

```swift
import Testing
@testable import Insights

/// One streamed reply, two audiences: passages for the voice interleaved
/// with sections for the screen. These pin the seam, the half-arrived
/// states a stream spends most of its time in, the cap, and how many
/// blocks each passage lets onto the screen.
@Suite struct SpokenTrackTests {
    private let threePassages = """
    SAY: Honestly, you slept well this week. Keep that wake time.

    Your sleep is more consistent this week.

    ## This week
    | Metric | Value |
    | --- | --- |
    | Average sleep | 7 h 24 min |
    | Recovery | 72% |

    SAY: Those two are up a notch on last week, and recovery is the one to watch.

    ## Next step
    - Start winding down 30 minutes before your usual bedtime.

    SAY: One small thing tonight, and that is plenty.
    """

    @Test func aWholeReplyParsesIntoSegmentsInOrder() {
        let track = SpokenTrack(parsing: threePassages)
        #expect(track.segments.count == 3)
        #expect(track.segments[0].spoken == "Honestly, you slept well this week. Keep that wake time.")
        #expect(track.segments[0].shown.hasPrefix("Your sleep is more consistent"))
        #expect(track.segments[1].spoken?.hasPrefix("Those two are up") == true)
        #expect(track.segments[1].shown.hasPrefix("## Next step"))
        #expect(track.segments[2].spoken == "One small thing tonight, and that is plenty.")
        #expect(track.segments[2].shown.isEmpty)
        #expect(!track.isOpeningPending)
        #expect(!track.shownText.contains("SAY:"))
        #expect(track.shownText.hasPrefix("Your sleep is more consistent"))
    }

    @Test func aStreamStillInsideTheOpeningShowsNothingYet() {
        let track = SpokenTrack(parsing: "SAY: Honestly, you slept we")
        #expect(track.opening == nil)
        #expect(track.shownText.isEmpty)
        #expect(track.isOpeningPending)
        #expect(SpokenTrack(parsing: "").isOpeningPending)
        #expect(SpokenTrack(parsing: "SA").isOpeningPending)
    }

    @Test func theOpeningIsCompleteTheMomentItsNewlineArrives() {
        let track = SpokenTrack(parsing: "SAY: You slept well.\n")
        #expect(track.opening == "You slept well.")
        #expect(track.shownText.isEmpty)
        #expect(!track.isOpeningPending)
    }

    @Test func aSecondPassageIsPendingUntilItsNewline() {
        let track = SpokenTrack(parsing: "SAY: Opening.\n\nA sentence.\n\nSAY: Half a passa")
        #expect(track.segments.count == 1)
        #expect(track.segments[0].shown == "A sentence.")
        let complete = SpokenTrack(parsing: "SAY: Opening.\n\nA sentence.\n\nSAY: Half a passage.\n")
        #expect(complete.segments.count == 2)
        #expect(complete.segments[1].spoken == "Half a passage.")
    }

    @Test func aSectionWithoutAPassageMergesIntoThePrevious() {
        let track = SpokenTrack(parsing: "SAY: Opening.\n\nFirst.\n\n## Second\nMore.\n")
        #expect(track.segments.count == 1)
        #expect(track.segments[0].shown == "First.\n\n## Second\nMore.")
        #expect(track.shownText == "First.\n\n## Second\nMore.")
    }

    @Test func aReplyWithoutAnyPassageIsOneSegmentShownWhole() {
        let text = "No recovery data is available yet."
        let track = SpokenTrack(parsing: text)
        #expect(track.segments.count == 1)
        #expect(track.segments[0].spoken == nil)
        #expect(track.segments[0].shown == text)
        #expect(track.shownText == text)
        #expect(!track.isOpeningPending)
    }

    @Test func thePrefixIsMatchedLooselyAndPassagesAreCleaned() {
        let track = SpokenTrack(parsing: "\n say: \"**Nice** work - 7h 24m tonight.\"\n\nDetail here.")
        #expect(track.opening == "Nice work, 7h 24m tonight.")
        #expect(track.shownText == "Detail here.")
    }

    @Test func anEmptyPassageCountsAsAbsent() {
        let track = SpokenTrack(parsing: "SAY:\n\nJust the answer.")
        #expect(track.opening == nil)
        #expect(track.shownText == "Just the answer.")
    }

    @Test func revealedBlocksAccumulate() {
        let track = SpokenTrack(parsing: threePassages)
        // Segment 0 shows a paragraph, a heading and a table: three blocks.
        #expect(track.revealedBlocks(throughSegment: 0) == 3)
        // Segment 1 adds a heading and a list: five.
        #expect(track.revealedBlocks(throughSegment: 1) == 5)
        // Segment 2 has no section of its own.
        #expect(track.revealedBlocks(throughSegment: 2) == 5)
        #expect(track.blockCount == 5)
    }

    @Test func cappingKeepsTheOpeningAndCutsAtSentences() {
        let track = SpokenTrack(parsing: threePassages)
        // Budget enough for the opening and part of the second passage.
        let capped = track.capped(to: 56 + 30)
        #expect(capped.segments[0].spoken == track.segments[0].spoken)
        #expect(capped.segments[1].spoken == nil)
        #expect(capped.segments[2].spoken == nil)
        #expect(capped.shownText == track.shownText)

        // A budget inside the opening itself trims it to a sentence, never to nothing.
        let tiny = track.capped(to: 30)
        #expect(tiny.segments[0].spoken == "Honestly, you slept well this week.")

        // Two whole passages fit; the third does not.
        let two = track.capped(to: 56 + 75)
        #expect(two.segments[1].spoken == track.segments[1].spoken)
        #expect(two.segments[2].spoken == nil)
    }

    @Test func theInstructionAsksForThePrefixAndTheWrittenRulesDoNot() {
        #expect(CoachPresentation.spokenTrackInstruction.contains(SpokenTrack.prefix))
        #expect(CoachPresentation.spokenTrackInstruction.contains("four"))
        #expect(!CoachPresentation.instruction.contains(SpokenTrack.prefix))
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter SpokenTrackTests`
Expected: compile errors, `cannot find 'SpokenTrack' in scope`.

- [ ] **Step 4: Write `SpokenTrack.swift`** (the whole file)

```swift
import Foundation

/// One reply, two audiences, interleaved.
///
/// The model writes a `SAY:` passage for the voice before each section it
/// writes for the screen. Splitting them on the phone rather than asking for
/// two completions keeps one call, one debit and one set of figures, and it
/// lets the voice start on the opening while the sections are still arriving.
///
/// Built from partial text as well as whole text, because a stream spends
/// most of its life half arrived: a `SAY:` line is a passage only once its
/// newline has landed, and the opening is pending while the text so far could
/// still turn out to begin with the prefix.
public struct SpokenTrack: Equatable, Sendable {
    /// What opens a passage. Matched without regard to case or leading
    /// whitespace, since a model that gets the word right and the case wrong
    /// has still done what it was asked.
    public static let prefix = "SAY:"

    /// A passage and the sections it introduces. The opening's `shown` is
    /// usually empty; a segment whose passage was dropped by the cap has
    /// `spoken == nil` and reveals with the passage before it.
    public struct Segment: Equatable, Sendable {
        public let spoken: String?
        public let shown: String
        public init(spoken: String?, shown: String) { self.spoken = spoken; self.shown = shown }
    }

    public let segments: [Segment]
    /// True while the text could still turn out to begin with a passage.
    public let isOpeningPending: Bool

    /// The first passage, which the voice reads first.
    public var opening: String? { segments.first?.spoken }

    /// Everything the screen renders and the transcript stores.
    public var shownText: String {
        segments.map(\.shown).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Rendered blocks across every segment.
    public var blockCount: Int { revealedBlocks(throughSegment: segments.count - 1) }

    public init(parsing text: String) {
        let trimmed = String(text.drop(while: { $0.isNewline || $0 == " " }))

        // One line so far: either the opening still being written, or a short
        // whole answer with no passage.
        if !trimmed.contains(where: \.isNewline) {
            if Self.couldBecomePrefix(trimmed) || Self.hasPrefix(trimmed) {
                segments = []
                isOpeningPending = true
            } else {
                segments = [Segment(spoken: nil, shown: trimmed)]
                isOpeningPending = false
            }
            return
        }

        let endsWithNewline = trimmed.last?.isNewline == true
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // A trailing `SAY:` line without its newline is still being written.
        if !endsWithNewline, let last = lines.last, Self.hasPrefix(last) {
            lines.removeLast()
        }

        var built: [(spoken: String?, lines: [String])] = []
        for line in lines {
            if Self.hasPrefix(line) {
                let passage = Self.cleanPassage(String(line.trimmingCharacters(in: .whitespaces).dropFirst(Self.prefix.count)))
                // An empty passage is no passage: its sections join the
                // segment before, rather than opening a silent one.
                if passage.isEmpty, !built.isEmpty { continue }
                built.append((spoken: passage.isEmpty ? nil : passage, lines: []))
            } else if built.isEmpty {
                built.append((spoken: nil, lines: [line]))
            } else {
                built[built.count - 1].lines.append(line)
            }
        }

        segments = built.map { Segment(spoken: $0.spoken, shown: $0.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)) }
        isOpeningPending = false
    }

    private init(segments: [Segment], isOpeningPending: Bool) {
        self.segments = segments; self.isOpeningPending = isOpeningPending
    }

    /// Rendered blocks in segments `0...index`, which is how many the screen
    /// may show once segment `index` has begun to play.
    public func revealedBlocks(throughSegment index: Int) -> Int {
        guard index >= 0 else { return 0 }
        return segments.prefix(index + 1).reduce(0) { $0 + CoachResponse($1.shown).blocks.count }
    }

    /// The passages trimmed to a character budget, in order. A passage that
    /// would cross the budget is cut at the last sentence end that fits;
    /// passages after the budget is spent become nil, so their sections
    /// reveal with the passage before. The opening is never dropped: with a
    /// budget inside it, it keeps its first sentence.
    public func capped(to characters: Int = 700) -> SpokenTrack {
        var remaining = max(characters, 0)
        var out: [Segment] = []
        for (index, segment) in segments.enumerated() {
            guard let spoken = segment.spoken else { out.append(segment); continue }
            if spoken.count <= remaining {
                remaining -= spoken.count
                out.append(segment)
            } else if index == 0 {
                let kept = Self.cut(spoken, to: remaining, keepAtLeastOneSentence: true)
                remaining = max(0, remaining - kept.count)
                out.append(Segment(spoken: kept, shown: segment.shown))
            } else {
                let kept = Self.cut(spoken, to: remaining, keepAtLeastOneSentence: false)
                remaining = max(0, remaining - kept.count)
                out.append(Segment(spoken: kept.isEmpty ? nil : kept, shown: segment.shown))
            }
        }
        return SpokenTrack(segments: out, isOpeningPending: isOpeningPending)
    }

    /// Cuts on a sentence boundary within `limit`. With `keepAtLeastOneSentence`
    /// the first sentence survives even when it is longer than the limit; a
    /// voice that says nothing is worse than one that runs a little long.
    private static func cut(_ text: String, to limit: Int, keepAtLeastOneSentence: Bool) -> String {
        let clipped = String(text.prefix(limit))
        if let lastStop = clipped.lastIndex(where: { ".!?".contains($0) }) {
            return String(clipped[...lastStop]).trimmingCharacters(in: .whitespaces)
        }
        guard keepAtLeastOneSentence else { return "" }
        if let firstStop = text.firstIndex(where: { ".!?".contains($0) }) {
            return String(text[...firstStop])
        }
        return text
    }

    private static func hasPrefix(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix(prefix)
    }

    private static func couldBecomePrefix(_ line: String) -> Bool {
        line.count < prefix.count && prefix.hasPrefix(line.uppercased())
    }

    /// The passage as a voice should get it: no markup, no dashes, and no
    /// quotation marks around the whole thing, which a model adds when told
    /// to write what it would say.
    private static func cleanPassage(_ raw: String) -> String {
        ResponseStyle.clean(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Edit `CoachResponse.swift`**

Delete the whole `public var spokenText: String { ... }` computed property. Replace `spokenLineInstruction` (the doc comment and the constant) with:

```swift
    /// Added behind `instruction` only when the reply will be read aloud.
    ///
    /// The voice gets its own passages rather than a flattening of the
    /// tables, because a table read out is a robot and a sentence said is a
    /// person. The opening is asked for first so it is the first thing to
    /// arrive: the voice starts on it while the rest is still being written,
    /// and each later passage lets its section onto the screen as it plays.
    public static let spokenTrackInstruction = """
    Your reply will be spoken aloud and shown on screen, and the two parts are different.
    Begin with exactly one line that starts with \(SpokenTrack.prefix) followed by what you \
    would actually say out loud: one or two short, warm sentences in plain spoken English, \
    the way a person talks to a friend, with at most one figure and no markdown, no list, \
    no table, no quotation marks. Do not read out the details; the screen shows them.
    Then a blank line, then the written answer following the rules above, in sections.
    Before each later section you may add one more line starting with \(SpokenTrack.prefix): \
    one or two sentences that say what that section shows and why it matters, again with at \
    most one figure and no markdown. It must not repeat the section's cells or sentences word \
    for word. At most four \(SpokenTrack.prefix) lines in the whole reply, each under 220 \
    characters. The written answer must not repeat any \(SpokenTrack.prefix) line word for word.
    """
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `cd LifeOSKit && swift test --filter "SpokenTrackTests|CoachResponseTests"`
Expected: every `SpokenTrackTests` test passes and `CoachResponseTests` still passes. If `revealedBlocksAccumulate` or the cap test fails on a count, the table-with-heading fixture is the thing to check (a heading and a table are two blocks; a paragraph before them is a third). Fix the parser, not the expectation.

- [ ] **Step 7: Commit**

```bash
git add -A LifeOSKit/Sources/Insights/SpokenReply.swift LifeOSKit/Sources/Insights/SpokenTrack.swift LifeOSKit/Tests/InsightsTests/SpokenReplyTests.swift LifeOSKit/Tests/InsightsTests/SpokenTrackTests.swift LifeOSKit/Sources/Insights/CoachResponse.swift
git commit -m "feat(insights): the spoken track, passages interleaved with sections

SpokenTrack replaces SpokenReply: a SAY passage per section, parsed from
the stream with pending states, a per-answer cap that never drops the
opening, and the block count each passage lets onto the screen. The table
flattening spokenText is deleted; nothing speaks a table."
```

---

### Task 2: `VoiceBudget`

**Files:**
- Create: `LifeOSKit/Sources/Insights/VoiceBudget.swift`
- Test: `LifeOSKit/Tests/InsightsTests/VoiceBudgetTests.swift`

**Interfaces:**
- Produces: `public struct VoiceBudget { static let monthlyAllowance = 30_000; init(defaults: UserDefaults, calendar: Calendar = .current); func used(now: Date = .now) -> Int; func remaining(now:) -> Int; func debit(_ characters: Int, now:); static func key(for: Date, calendar:) -> String }`. Task 5 and Task 6 consume it.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import Insights

@Suite struct VoiceBudgetTests {
    private func fresh() -> (VoiceBudget, UserDefaults) {
        let suite = "test.voice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        return (VoiceBudget(defaults: defaults, calendar: calendar), defaults)
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func debitsAccumulateWithinAMonth() {
        let (budget, _) = fresh()
        let october = date(2026, 10, 6)
        #expect(budget.used(now: october) == 0)
        #expect(budget.remaining(now: october) == VoiceBudget.monthlyAllowance)
        budget.debit(400, now: october)
        budget.debit(250, now: date(2026, 10, 20))
        #expect(budget.used(now: october) == 650)
        #expect(budget.remaining(now: october) == VoiceBudget.monthlyAllowance - 650)
    }

    @Test func aNewMonthStartsFresh() {
        let (budget, _) = fresh()
        budget.debit(VoiceBudget.monthlyAllowance, now: date(2026, 10, 31))
        #expect(budget.remaining(now: date(2026, 10, 31)) == 0)
        #expect(budget.used(now: date(2026, 11, 1)) == 0)
        #expect(budget.remaining(now: date(2026, 11, 1)) == VoiceBudget.monthlyAllowance)
    }

    @Test func remainingNeverGoesNegativeAndTheKeyNamesTheMonth() {
        let (budget, _) = fresh()
        budget.debit(VoiceBudget.monthlyAllowance + 5_000, now: date(2026, 10, 6))
        #expect(budget.remaining(now: date(2026, 10, 6)) == 0)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(VoiceBudget.key(for: date(2026, 10, 6), calendar: calendar) == "voice.characters.2026-10")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter VoiceBudgetTests`
Expected: `cannot find 'VoiceBudget' in scope`.

- [ ] **Step 3: Write the value**

```swift
import Foundation

/// How much premium voice an account has used this month, in characters
/// sent for synthesis. Speech is billed per character, so this is the unit
/// the bill is in. A month is the account's own calendar month; the key
/// names it so a new month starts at zero without anything being reset.
public struct VoiceBudget: Sendable {
    /// About forty narrated answers at the per-answer cap, and about a
    /// dollar fifty at the published Flash rate: inside the cost ceiling with
    /// room for the rest of the stack.
    public static let monthlyAllowance = 30_000

    private let defaults: UserDefaults
    private let calendar: Calendar

    public init(defaults: UserDefaults, calendar: Calendar = .current) {
        self.defaults = defaults; self.calendar = calendar
    }

    public static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "voice.characters.%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public func used(now: Date = .now) -> Int {
        defaults.integer(forKey: Self.key(for: now, calendar: calendar))
    }

    public func remaining(now: Date = .now) -> Int {
        max(0, Self.monthlyAllowance - used(now: now))
    }

    public func debit(_ characters: Int, now: Date = .now) {
        let key = Self.key(for: now, calendar: calendar)
        defaults.set(defaults.integer(forKey: key) + max(0, characters), forKey: key)
    }
}
```

`VoiceBudget` is `Sendable` because `UserDefaults` is; if the compiler disagrees on this toolchain, mark the struct `@unchecked Sendable` with a one-line comment that `UserDefaults` is thread-safe.

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter VoiceBudgetTests`
Expected: `3 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/VoiceBudget.swift LifeOSKit/Tests/InsightsTests/VoiceBudgetTests.swift
git commit -m "feat(insights): a monthly character budget for the premium voice"
```

---

### Task 3: `VoicePlayer` plays a queue

**Files:**
- Modify: `LIfeOS/Features/Coach/Model/ElevenLabsVoiceClient.swift` (the `VoicePlayer` class only)

**Interfaces:**
- Produces: `struct VoiceSegment { let index: Int; let audio: Data }`; on `VoicePlayer`: `var onSegmentStart: ((Int) -> Void)?`, `var onFinish: (() -> Void)?`, `func play(_ segments: [VoiceSegment])`, `func append(_ segments: [VoiceSegment])`, `func play(_ data: Data)` (one segment, index 0, kept for callers), `stop()` clears the queue; `isSpeaking` is true from the first start to the last end. Task 5 consumes them.

- [ ] **Step 1: Replace the `VoicePlayer` class**

Replace everything from `/// Plays what the client returns.` to the end of the file with:

```swift
/// One passage of audio and which segment of the track it belongs to.
struct VoiceSegment {
    let index: Int
    let audio: Data
}

/// Plays what the clients return, in order.
///
/// Holds the player because `AVAudioPlayer` stops the moment it is
/// deallocated, which is the classic way a sound plays for a tenth of a second
/// and no longer. Plays a queue so a narration of several passages is one
/// `isSpeaking` from first start to last end, and tells the screen which
/// passage has just begun so the section it belongs to can come up with it.
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    private(set) var level: CGFloat = 0
    /// Called the moment a segment begins to play, with its index.
    var onSegmentStart: ((Int) -> Void)?
    /// Called once, when the last queued segment has ended or playback was stopped.
    var onFinish: (() -> Void)?

    private var player: AVAudioPlayer?
    private var meteringTask: Task<Void, Never>?
    private var queue: [VoiceSegment] = []

    /// Starts a fresh narration. Anything playing stops first.
    func play(_ segments: [VoiceSegment]) {
        stop(notifying: false)
        queue = segments
        playNext()
    }

    /// Adds passages to a narration already under way. If nothing is playing
    /// (the earlier passages have all ended), they start at once.
    func append(_ segments: [VoiceSegment]) {
        queue.append(contentsOf: segments)
        if player == nil { playNext() }
    }

    /// One passage, as the old single-line voice used it.
    func play(_ data: Data) { play([VoiceSegment(index: 0, audio: data)]) }

    func stop() { stop(notifying: true) }

    private func stop(notifying: Bool) {
        let wasSpeaking = isSpeaking || !queue.isEmpty
        meteringTask?.cancel()
        meteringTask = nil
        level = 0
        player?.stop()
        player = nil
        queue = []
        isSpeaking = false
        // Handed back so a podcast or a playlist returns to full volume rather
        // than staying ducked until the app is killed.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if notifying, wasSpeaking { onFinish?() }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            if isSpeaking { stop(notifying: true) }
            return
        }
        let segment = queue.removeFirst()
        do {
            // Spoken word, so it ducks other audio rather than stopping it, and
            // it plays through the speaker rather than the earpiece.
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(data: segment.audio)
            player.delegate = self
            self.player = player
            player.isMeteringEnabled = true
            guard player.play() else { playNext(); return }
            isSpeaking = true
            onSegmentStart?(segment.index)
            meteringTask?.cancel()
            meteringTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let player = self.player else { break }
                    guard player.isPlaying else { break }
                    player.updateMeters()
                    self.level = CGFloat(AudioEnvelope.level(decibels: Double(player.averagePower(forChannel: 0))))
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        } catch {
            // A passage that cannot be decoded is skipped, not fatal: the
            // next one still plays and the screen still fills.
            playNext()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // A delayed completion from an old player must not advance a newer narration.
        let finished = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == finished else { return }
            self.player = nil
            self.level = 0
            self.playNext()
        }
    }
}
```

- [ ] **Step 2: Do not build yet**

`CoachViewModel` still names `SpokenReply`, which Task 1 removed; Task 5 fixes that. Move on.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Coach/Model/ElevenLabsVoiceClient.swift
git commit -m "feat(coach): the voice player plays a queue and reports each start

Does not build alone; the view model that drives it follows."
```

---

### Task 4: `DeviceVoiceClient`

**Files:**
- Create: `LIfeOS/Features/Coach/Model/DeviceVoiceClient.swift`

**Interfaces:**
- Produces: `enum DeviceVoiceClient { static func speech(for text: String, locale: Locale = .current) async throws -> Data }` returning WAV data the `VoicePlayer` can play. Task 5 consumes it when the budget is spent.

- [ ] **Step 1: Write the client**

```swift
import AVFoundation
import Foundation

/// Apple's on-device voice, rendered to audio data rather than spoken live,
/// so the same `VoicePlayer` queue carries it and the screen's reveal is
/// driven the same way. The fallback for when the month's premium allowance
/// is spent: free, offline, and never silent.
nonisolated enum DeviceVoiceClient {
    enum Failure: Error { case noAudio }

    /// The best installed voice for the locale: premium, then enhanced, then
    /// whatever the system has.
    static func voice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let language = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(String(language.prefix(2)))
        }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    static func speech(for text: String, locale: Locale = .current) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let synthesizer = AVSpeechSynthesizer()
        var pcm = Data()
        var format: AVAudioFormat?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard let buffer = buffer as? AVAudioPCMBuffer else { return }
                if buffer.frameLength == 0 {
                    // The empty buffer is the end marker.
                    if !finished { finished = true; continuation.resume() }
                    return
                }
                format = buffer.format
                pcm.append(Self.bytes(of: buffer))
            }
        }

        guard let format, !pcm.isEmpty else { throw Failure.noAudio }
        return Self.wav(pcm: pcm, format: format)
    }

    /// Interleaved sample bytes from a buffer in whatever format the
    /// synthesiser produced (float32 or int16, mono or stereo).
    private static func bytes(of buffer: AVAudioPCMBuffer) -> Data {
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        var data = Data()
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let floats = buffer.floatChannelData else { return data }
            data.reserveCapacity(frames * channels * 4)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    var sample = floats[channel][frame]
                    data.append(Data(bytes: &sample, count: 4))
                }
            }
        case .pcmFormatInt16:
            guard let ints = buffer.int16ChannelData else { return data }
            data.reserveCapacity(frames * channels * 2)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    var sample = ints[channel][frame]
                    data.append(Data(bytes: &sample, count: 2))
                }
            }
        default:
            break
        }
        return data
    }

    /// A WAV container around the samples. Format 3 is IEEE float, format 1
    /// is PCM integer; `AVAudioPlayer` reads both.
    private static func wav(pcm: Data, format: AVAudioFormat) -> Data {
        let isFloat = format.commonFormat == .pcmFormatFloat32
        let bitsPerSample: UInt16 = isFloat ? 32 : 16
        let channels = UInt16(format.channelCount)
        let sampleRate = UInt32(format.sampleRate)
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)

        var header = Data()
        func put<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; header.append(Data(bytes: &v, count: MemoryLayout<T>.size)) }
        header.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(isFloat ? 3 : 1)); put(channels); put(sampleRate); put(byteRate); put(blockAlign); put(bitsPerSample)
        header.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return header + pcm
    }
}
```

- [ ] **Step 2: Commit** (the build comes with Task 5)

```bash
git add LIfeOS/Features/Coach/Model/DeviceVoiceClient.swift
git commit -m "feat(coach): render the device voice to audio data for the player queue"
```

---

### Task 5: Narration in `CoachViewModel`

**Files:**
- Modify: `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift`

**Interfaces:**
- Consumes: `SpokenTrack`, `VoiceBudget`, `CoachPresentation.spokenTrackInstruction` (Task 1, 2); `VoicePlayer` queue API (Task 3); `DeviceVoiceClient.speech(for:)` (Task 4).
- Produces: `var revealedBlocks: Int?` (nil means every block), `var voiceNotice: String?`, `var synthesize: (String, AssistantVoice, String) async throws -> Data` (injectable; default ElevenLabs), `#if DEBUG func previewNarrate(_ reply: String)`. Task 6 and Task 7 consume them.

- [ ] **Step 1: State and dependencies**

Add after `private var spokeThisTurn = false`:

```swift
    /// How many rendered blocks of the answer in flight may be on screen:
    /// nil is all of them. Set from the voice as each passage starts, so a
    /// section arrives with the sentence about it rather than before it.
    var revealedBlocks: Int?
    /// One quiet line for the voice screen: `Premium voice resumes on the 1st`
    /// while the month's allowance is spent, otherwise nil.
    var voiceNotice: String?
    /// The track of the turn in flight, kept so a passage that starts late
    /// can still be mapped to its blocks.
    private var currentTrack: SpokenTrack?
    private var narrationTask: Task<Void, Never>?
    private let voiceBudget = VoiceBudget(defaults: .currentAccount)
    /// The premium synthesiser. A closure so a design preview can hand in a
    /// stub that returns a moment of silence and the staged reveal can be
    /// captured without a key or a network.
    var synthesize: (_ text: String, _ voice: AssistantVoice, _ apiKey: String) async throws -> Data = {
        try await ElevenLabsVoiceClient.speech(for: $0, voice: $1, apiKey: $2)
    }
```

- [ ] **Step 2: Replace `speak(_:turn:)`, `received(_:)` and `fallbackSpokenLine`**

Replace the `speak(_ text: String, turn: UUID)` method with:

```swift
    /// Reads the track aloud, passage by passage, and lets each passage's
    /// sections onto the screen as it starts.
    ///
    /// Fire and forget, and deliberately not awaited by `send`. Passages are
    /// fetched in order, the next while the current plays, so there is never
    /// a gap longer than one fetch. Every passage is debited against the
    /// month's allowance before it is sent; once the allowance is spent the
    /// device voice takes over for the rest of the month. A fetch that fails
    /// is skipped and its sections reveal with the next start, or at once if
    /// it was the last. Whatever happens to the audio, the whole answer is on
    /// screen by the end, because silence is acceptable and a blank screen
    /// is not. The turn id keeps a late exit from an old reply from touching
    /// a new one.
    private func narrate(_ track: SpokenTrack, turn: UUID) {
        let passages = track.segments.enumerated().compactMap { index, segment in
            segment.spoken.map { (index: index, text: $0) }
        }
        guard voiceAvailable, let key = AppConfig.elevenLabsAPIKey, !passages.isEmpty else {
            reveal(turn)
            revealedBlocks = nil
            return
        }
        currentTrack = track
        let voice = AssistantVoice(rawValue: UserDefaults.standard.string(forKey: AssistantVoice.voiceKey) ?? "") ?? .default
        let player = voicePlayer
        player.onSegmentStart = { [weak self] index in
            guard let self, turn == self.turnID else { return }
            self.reveal(turn)
            self.revealedBlocks = self.currentTrack?.revealedBlocks(throughSegment: index)
        }
        player.onFinish = { [weak self] in
            guard let self, turn == self.turnID else { return }
            self.reveal(turn)
            self.revealedBlocks = nil
        }

        narrationTask?.cancel()
        narrationTask = Task { [weak self] in
            var started = false
            for passage in passages {
                guard !Task.isCancelled, let self else { return }
                let audio: Data?
                if self.voiceBudget.remaining() >= passage.text.count {
                    self.voiceBudget.debit(passage.text.count)
                    self.voiceNotice = nil
                    audio = try? await self.synthesize(passage.text, voice, key)
                } else {
                    self.voiceNotice = "Premium voice resumes on the 1st"
                    audio = try? await DeviceVoiceClient.speech(for: passage.text)
                }
                guard !Task.isCancelled, turn == self.turnID else { return }
                guard let audio else {
                    // Skipped: its sections come up with the next passage, or now.
                    if passage.index == passages.last?.index, !started {
                        self.reveal(turn); self.revealedBlocks = nil
                    }
                    continue
                }
                let segment = VoiceSegment(index: passage.index, audio: audio)
                if started { player.append([segment]) } else { player.play([segment]); started = true }
            }
            if !started, let self { self.reveal(turn); self.revealedBlocks = nil }
        }
    }
```

Replace `received(_ text: String)` with:

```swift
    /// A chunk of the answer as written so far.
    ///
    /// The opening is read the moment its line lands, while the sections are
    /// still arriving; the later passages are queued when the reply is whole,
    /// in `send`, since a passage is only a passage once its newline has.
    private func received(_ text: String) {
        let track = SpokenTrack(parsing: text)
        latestShown = track.shownText
        if holdingAnswer {
            if !spokeThisTurn, let opening = track.opening {
                spokeThisTurn = true
                currentTrack = track
                narrate(SpokenTrack(parsing: "\(SpokenTrack.prefix) \(opening)\n"), turn: turnID)
            }
        } else {
            answer = track.shownText
        }
    }
```

Replace `fallbackSpokenLine` with:

```swift
    /// What to say when the model was asked for a track and wrote no passage
    /// at all: the first plain sentence or two of the answer, once, never a
    /// table read aloud.
    private static func fallbackTrack(for shown: String) -> SpokenTrack? {
        for block in CoachResponse(shown).blocks {
            if case .paragraph(let text) = block {
                return SpokenTrack(parsing: "\(SpokenTrack.prefix) \(ResponseStyle.clean(text))\n\n\(shown)")
            }
        }
        return nil
    }
```

- [ ] **Step 3: The end of `send`**

Replace the block from `let final = SpokenReply(parsing: reply.text)` through the `if holdingAnswer { ... } else { finish(turn) }` with:

```swift
                // The passages are for the voice and nobody else: not
                // rendered, not kept in the transcript, and not written to the
                // store the next prompt is built from. A reply that was only
                // an opening is shown as itself rather than as nothing.
                let final = SpokenTrack(parsing: reply.text).capped(to: 700)
                let shown = final.shownText.isEmpty ? (final.opening ?? reply.text) : final.shownText
                try? store.append(conversationID: conversationID, role: .assistant, text: shown)
                let turn = LifoTurn(question: question, answer: shown, sent: sent)
                phase = .answered
                status = "LIFO"
                if holdingAnswer {
                    heldTurn = turn
                    latestShown = shown
                    currentTrack = final
                    if spokeThisTurn {
                        // The opening is already playing; queue the rest.
                        let rest = final.segments.enumerated().dropFirst().compactMap { index, segment in
                            segment.spoken.map { (index: index, text: $0) }
                        }
                        if !rest.isEmpty { appendPassages(rest, turn: turnID) }
                    } else {
                        spokeThisTurn = true
                        if let track = final.opening != nil ? final : Self.fallbackTrack(for: shown) {
                            narrate(track, turn: turnID)
                        } else {
                            reveal(turnID)
                            revealedBlocks = nil
                        }
                    }
                    // Whatever the voice does, the answer is on screen within
                    // two seconds of being finished. A slow synthesis is a
                    // reason to read first, not a reason to see nothing.
                    let id = turnID
                    revealTimeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        self?.reveal(id)
                    }
                } else {
                    finish(turn)
                }
```

And add, next to `narrate`:

```swift
    /// The passages after the opening, fetched in order and appended to the
    /// narration already playing. Same budget, same fallback, same guards.
    private func appendPassages(_ passages: [(index: Int, text: String)], turn: UUID) {
        guard let key = AppConfig.elevenLabsAPIKey else { return }
        let voice = AssistantVoice(rawValue: UserDefaults.standard.string(forKey: AssistantVoice.voiceKey) ?? "") ?? .default
        let player = voicePlayer
        let previous = narrationTask
        narrationTask = Task { [weak self] in
            await previous?.value
            for passage in passages {
                guard !Task.isCancelled, let self, turn == self.turnID else { return }
                let audio: Data?
                if self.voiceBudget.remaining() >= passage.text.count {
                    self.voiceBudget.debit(passage.text.count)
                    audio = try? await self.synthesize(passage.text, voice, key)
                } else {
                    self.voiceNotice = "Premium voice resumes on the 1st"
                    audio = try? await DeviceVoiceClient.speech(for: passage.text)
                }
                guard !Task.isCancelled, turn == self.turnID, let audio else { continue }
                player.append([VoiceSegment(index: passage.index, audio: audio)])
            }
        }
    }
```

- [ ] **Step 4: Reveal and stop keep the blocks honest**

In `reveal(_ turn: UUID)`, the method body stays; `revealedBlocks` is set by the callers above. In `stopSpeaking()`, add `narrationTask?.cancel(); narrationTask = nil; revealedBlocks = nil` before `voicePlayer.stop()`. In `send`, where `spokeThisTurn = false` and `holdingAnswer = voiceAvailable` are set at the start of a turn, add `revealedBlocks = holdingAnswer ? 0 : nil` and `currentTrack = nil`. In `fail(_:)`, add `revealedBlocks = nil`. In `finish(_:)`, add `revealedBlocks = nil`.

- [ ] **Step 5: The instruction**

In `coachInstructions(_:for:spokenLine:)`, replace `CoachPresentation.spokenLineInstruction` with `CoachPresentation.spokenTrackInstruction`. The parameter name `spokenLine` may stay; it means the same decision.

- [ ] **Step 6: The preview hook**

At the end of the class, inside `#if DEBUG`:

```swift
    #if DEBUG
    /// Runs the post-reply path on a canned reply, for the design preview:
    /// holds the answer, narrates through `synthesize`, reveals per passage.
    func previewNarrate(_ reply: String) {
        turnID = UUID()
        spokeThisTurn = false
        holdingAnswer = true
        revealedBlocks = 0
        pendingQuestion = "Give me a quick look at my week."
        phase = .answered
        let final = SpokenTrack(parsing: reply).capped(to: 700)
        let shown = final.shownText
        heldTurn = LifoTurn(question: pendingQuestion, answer: shown)
        latestShown = shown
        currentTrack = final
        spokeThisTurn = true
        narrate(final, turn: turnID)
    }
    #endif
```

`voiceAvailable` requires `isVisible`, `voiceScreenActive`, the Settings toggle and a key; the preview sets the first two through the screen and the toggle through `UserDefaults.standard`, and `AppConfig.elevenLabsAPIKey` must be non-nil for `narrate` to proceed. If the preview build has no key, `narrate` reveals at once and the staged capture shows everything. Task 7 handles this by letting the preview inject a dummy key path: see its Step 1.

- [ ] **Step 7: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet > /tmp/build-track5.log 2>&1; echo "build exit $?"; grep -E "error:" /tmp/build-track5.log | sed 's|.*/LIfeOS/||' | sort -u | head
grep -rn "SpokenReply\|spokenLineInstruction\|spokenText" --include='*.swift' LIfeOS LifeOSKit || echo "no stale names"
```

Expected: `build exit 0`, `no stale names`. A `Sendable` complaint about the `synthesize` closure capturing `self` in the `Task` is fixed by capturing `let synthesize = self.synthesize` before the task and calling that.

- [ ] **Step 8: Commit**

```bash
git add LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift
git commit -m "feat(coach): narrate the reply passage by passage and reveal each section as it plays

The opening is read the moment it lands; the later passages queue when
the reply is whole. Each passage is debited against the month's
allowance, and the device voice carries the rest of the month once it is
spent. revealedBlocks tells the screen how much of the answer may show."
```

---

### Task 6: The screen reveals with the voice; Settings shows the usage

**Files:**
- Modify: `LIfeOS/Features/Coach/View/CoachResponseView.swift` (add `revealed`)
- Modify: `LIfeOS/Features/Coach/View/LifoCoachScreen.swift` (pass it; the notice line)
- Modify: `LIfeOS/Features/Settings/View/SettingsScreen.swift` (usage line)

**Interfaces:**
- Consumes: `CoachViewModel.revealedBlocks`, `.voiceNotice` (Task 5); `VoiceBudget` (Task 2).
- Produces: `CoachResponseView(text: String, revealed: Int? = nil)`.

- [ ] **Step 1: `CoachResponseView`**

Add `var revealed: Int? = nil` under `let text: String`, and change the `ForEach` to iterate the revealed prefix:

```swift
    var body: some View {
        let blocks = CoachResponse(text).blocks
        let shown = revealed.map { Array(blocks.prefix($0)) } ?? blocks
        return VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .modifier(BlockReveal(index: index))
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
```

`BlockReveal` keeps its per-block state, so blocks already shown are never re-animated when `revealed` grows; a new block enters with the usual rise.

- [ ] **Step 2: `LifoCoachScreen`**

In both places the answer in flight is drawn (the text transcript and the voice screen), pass the model's count: `CoachResponseView(text: model.answer, revealed: model.revealedBlocks)`. History turns keep `CoachResponseView(text: turn.answer)`. Under the `AudioWaveform` in `voiceScreen`, add:

```swift
                if let notice = model.voiceNotice {
                    Text(notice).font(LifeOSType.caption).foregroundStyle(quiet)
                }
```

- [ ] **Step 3: Settings**

In `SettingsScreen.swift`, inside `if speaksReplies { ... }` after the `ForEach(AssistantVoice.allCases)` block, add the usage line:

```swift
                    Text("\(VoiceBudget(defaults: .currentAccount).used().formatted()) of \(VoiceBudget.monthlyAllowance.formatted()) characters this month")
                        .font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .padding(.top, 4)
```

Add `import Insights` at the top of the file if it is not already imported.

- [ ] **Step 4: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet > /tmp/build-track6.log 2>&1; echo "build exit $?"; grep -E "error:" /tmp/build-track6.log | sed 's|.*/LIfeOS/||' | sort -u | head
```

Expected: `build exit 0`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Coach/View/CoachResponseView.swift LIfeOS/Features/Coach/View/LifoCoachScreen.swift LIfeOS/Features/Settings/View/SettingsScreen.swift
git commit -m "feat(coach): reveal each section as its passage plays, and show the month's voice usage"
```

---

### Task 7: The preview narrates a canned reply

**Files:**
- Modify: `LIfeOS/Features/Coach/View/CoachDesignPreview.swift`
- Modify: `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift` (`voiceAvailable`, DEBUG override)

**Interfaces:**
- Consumes: `CoachViewModel.previewNarrate(_:)`, `.synthesize` (Task 5).
- Produces: `coach-voice --track=3` (staged reveal through a stub synthesiser returning 0.8 s of silence), `--fail=N` (the stub refuses segment N), `--budget-spent` (the allowance is debited first, so the device voice and the notice line show).

- [ ] **Step 1: Let the preview satisfy `voiceAvailable` without a key**

In `CoachViewModel`, add under the DEBUG section: `var previewVoiceKey: String?`, and in `voiceAvailable` and the two `AppConfig.elevenLabsAPIKey` reads in `narrate`/`appendPassages`, read a computed `private var voiceKey: String? { #if DEBUG previewVoiceKey ?? AppConfig.elevenLabsAPIKey #else AppConfig.elevenLabsAPIKey #endif }` instead. Write it as:

```swift
    private var voiceKey: String? {
        #if DEBUG
        if let previewVoiceKey { return previewVoiceKey }
        #endif
        return AppConfig.elevenLabsAPIKey
    }
```

and replace the three `AppConfig.elevenLabsAPIKey` reads with `voiceKey`.

- [ ] **Step 2: The preview**

In `CoachDesignPreview.swift`, replace the `.task` and add the stub:

```swift
    var body: some View {
        LifoCoachScreen(model: model, onDismiss: {}, initialMode: page == "coach-voice" ? .voice : .text)
            .task {
                let args = ProcessInfo.processInfo.arguments
                if page != "coach-empty", !args.contains(where: { $0.hasPrefix("--track=") }) {
                    model.history = [LifoTurn(question: "Give me a quick look at my week.", answer: Self.sample)]
                }
                if page == "coach-voice" {
                    if args.contains(where: { $0.hasPrefix("--track=") }) {
                        let failing = args.first { $0.hasPrefix("--fail=") }.flatMap { Int($0.dropFirst(7)) }
                        var calls = 0
                        model.previewVoiceKey = "preview"
                        UserDefaults.standard.set(true, forKey: AssistantVoice.enabledKey)
                        model.synthesize = { _, _, _ in
                            calls += 1
                            if let failing, calls == failing + 1 { throw VoiceSynthesisError.remoteFailed }
                            return Self.silence(seconds: 0.8)
                        }
                        if args.contains("--budget-spent") {
                            VoiceBudget(defaults: .currentAccount).debit(VoiceBudget.monthlyAllowance)
                        }
                        try? await Task.sleep(for: .milliseconds(600))
                        model.previewNarrate(Self.narrated)
                    } else {
                        await animateListening()
                    }
                }
            }
    }

    /// A WAV of silence, so the player runs for a known time and the reveal
    /// can be watched frame by frame.
    static func silence(seconds: Double) -> Data {
        let sampleRate: UInt32 = 16_000
        let frames = Int(Double(sampleRate) * seconds)
        let pcm = Data(count: frames * 2)
        var header = Data()
        func put<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; header.append(Data(bytes: &v, count: MemoryLayout<T>.size)) }
        header.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1)); put(sampleRate); put(sampleRate * 2); put(UInt16(2)); put(UInt16(16))
        header.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return header + pcm
    }

    /// The sample reply with three passages, the shape the spoken track asks for.
    static let narrated = """
    SAY: Honestly, you slept well this week. Keep that wake time.

    Your week, at a glance. Here are the numbers you've recorded.

    | Metric | This week |
    | --- | --- |
    | Average sleep | 7h 24m |
    | Recovery | 72% |

    SAY: Both are up a notch on last week, and recovery is the one to watch.

    ## Compared with last week
    | Measure | Last week | This week |
    | --- | --- | --- |
    | Steps / day | 7,420 | 8,610 |
    | Sleep | 7h 02m | 7h 24m |

    SAY: One small thing tonight, and that is plenty.

    ## Next up
    - Review your latest sleep entries.
    - Pick one priority for tomorrow.
    """
```

Add `import Insights` at the top of the preview file. The `--budget-spent` debit writes into the signed-out account suite on the simulator (`lifeos.signedOut`), which is the preview's own; it does not touch a real account.

- [ ] **Step 3: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet > /tmp/build-track7.log 2>&1; echo "build exit $?"; grep -E "error:" /tmp/build-track7.log | sed 's|.*/LIfeOS/||' | sort -u | head
```

Expected: `build exit 0`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Coach/View/CoachDesignPreview.swift LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift
git commit -m "feat(coach): the voice preview narrates a canned reply through a stub synthesiser"
```

---

### Task 8: Captures and gates

- [ ] **Step 1: Install and capture the staged reveal**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/lifo-spoken-track
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/lifo-spoken-track/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/2742294b-e1ce-435a-8249-500b00fd3085/scratchpad
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
# Three frames of the staged reveal: the stub plays 0.8 s per passage after a 0.6 s wait.
xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview --page=coach-voice --track=3 >/dev/null
perl -e 'select(undef,undef,undef,1.2)'; xcrun simctl io $SIM screenshot "$OUT/pr-track-frame1.png" >/dev/null
perl -e 'select(undef,undef,undef,0.8)'; xcrun simctl io $SIM screenshot "$OUT/pr-track-frame2.png" >/dev/null
perl -e 'select(undef,undef,undef,0.8)'; xcrun simctl io $SIM screenshot "$OUT/pr-track-frame3.png" >/dev/null
perl -e 'select(undef,undef,undef,2.0)'; xcrun simctl io $SIM screenshot "$OUT/pr-track-done.png" >/dev/null
capture() { local name=$1; shift; xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null; xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null; perl -e 'select(undef,undef,undef,5)'; xcrun simctl io $SIM screenshot "$OUT/pr-track-$name.png" >/dev/null; }
capture fail2 --page=coach-voice --track=3 --fail=2
capture budget --page=coach-voice --track=3 --budget-spent
capture budget-dark --page=coach-voice --track=3 --budget-spent --dark
capture voice --page=coach-voice
capture coach --page=coach
ls -la $OUT/pr-track-*.png
```

- [ ] **Step 2: Review the captures**

- `frame1`: the question block and, at most, the first segment's blocks (the sentence, the eyebrow and two cells); the comparison table and the steps are not yet on screen. The waveform is in the accent (speaking).
- `frame2` or `frame3`: the comparison heading and table have appeared; the steps appear by `frame3` or `done`.
- `done`: every block on screen, waveform back to ink, no notice line.
- `fail2`: every block on screen by the end, although the stub refused the third passage; nothing is missing.
- `budget`: the quiet line `Premium voice resumes on the 1st` under the waveform; all blocks on screen by the end (the device voice played them, or the reveal timeout did on a simulator without voices).
- `budget-dark`: the same in dark.
- `voice`, `coach`: unchanged from PR #22.

If the frames do not show a staged reveal (everything at once in `frame1`), the likely causes are `voiceAvailable` false (the Settings toggle or `isVisible`) or `reveal(turn)` setting `revealedBlocks = nil` somewhere it should not; fix in the view model and recapture. Record each capture in the ledger.

- [ ] **Step 3: Gates**

```bash
(cd LifeOSKit && swift test 2>&1 | tail -2)
scripts/check-typography.sh > /tmp/typo-track.txt 2>&1
diff <(sed 's/^[^:]*://' /tmp/typo-track-base.txt | sort) <(sed 's/^[^:]*://' /tmp/typo-track.txt | sort) | grep '^>' || echo "typography: no new violations"
```

Expected: the suite passes with the new `SpokenTrackTests` and `VoiceBudgetTests`; `typography: no new violations`.

---

### Task 9: Open the pull request

- [ ] **Step 1: Rebase and push**

```bash
git fetch origin
if git merge-base --is-ancestor origin/feat/editorial-coach origin/main; then BASE=main; git rebase origin/main; else BASE=feat/editorial-coach; git rebase origin/feat/editorial-coach; fi
echo "base: $BASE"
git push -u origin feat/lifo-spoken-track
```

- [ ] **Step 2: Open the PR** (no attribution footer)

```bash
gh pr create --base $BASE --head feat/lifo-spoken-track \
  --title "feat(coach): LIFO narrates the screen, a passage per section" \
  --body "$(cat <<'EOF'
## Summary

- The model writes a spoken passage before each section of its written answer; `SpokenTrack` splits the stream into passages and sections, with pending states for a stream still inside a line. The opening is read the moment it lands; the later passages queue when the reply is whole.
- Each section appears the moment its passage starts to play: `VoicePlayer` plays a queue and reports each start, and `CoachResponseView` draws only the revealed blocks. Everything is on screen by the end whatever the audio does.
- Passages are capped at 700 characters per answer, never dropping the opening, and debited against a 30,000-character monthly allowance per account; once it is spent, Apple's device voice renders the passages to audio for the same queue and the voice screen says `Premium voice resumes on the 1st`. Settings shows the month's usage under the voice picker.
- `CoachResponse.spokenText`, the table flattening, is deleted. Nothing speaks a table.
- Spec: docs/superpowers/specs/2026-10-06-lifo-spoken-track-design.md. Plan: docs/superpowers/plans/2026-10-06-lifo-spoken-track.md.

## Verification

- LifeOSKit `swift test`: all suites pass, including `SpokenTrackTests` and `VoiceBudgetTests`.
- `scripts/check-typography.sh`: no new violations.
- Simulator `coach-voice --track=3` through a stub synthesiser: four frames showing the staged reveal; `--fail=2` with every block on screen after a refused passage; `--budget-spent` with the notice line, light and dark.
EOF
)"
```

- [ ] **Step 3: Report** the PR link, the capture paths, the merge order (#21, #22, then this), and that the calendar find-and-ask PR is next.
