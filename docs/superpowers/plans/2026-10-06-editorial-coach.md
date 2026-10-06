# Editorial LIFO and calendar assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the LIFO coach screen and the calendar assistant sheet on the editorial theme: paper and ink that follow the system colour scheme, a masthead and bare glyphs instead of the aura header, hairline-outlined questions, replies on paper with hairline tables and numbered steps, one shared composer, a plain ink waveform in place of the orb, and the aura, orb and LIFO palette deleted.

**Architecture:** The wording that can be wrong (`VoiceHeadline`, `AssistantHeadline`) lives in tested values in `DesignSystem`, beside `TodayHeadline`. The pieces both chat screens share (`ChatTurn`, `ChatComposer`, `ChatThinking`, `ChatConfirmation`, `ChatToolTags`, `AudioWaveform`, `WrapLayout`) move into `DesignSystem` as public views. `CoachResponseView` loses its aura mode and draws blocks with editorial pieces. `LifoCoachScreen` and `AssistantSheet` are rewritten on paper around those pieces; `AssistantAgendaCard` is restyled in place. `LifoAura.swift` and `CoachVoiceOrb.swift` are deleted, and `CoachScreenStyle` shrinks to its two cases. DEBUG preview pages render both screens from fixtures, with a `#if DEBUG` hook on `AssistantViewModel` so the connected state can be shown without calendar access.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-05-editorial-shell-life-today-notes-coach-guide-design.md`, section 5 (Chat), with section 7 (preview pages `coach`, `coach-voice`, `assistant`) and the rules at its head. PR 2 of the order fixed in `docs/superpowers/specs/2026-10-06-editorial-calendar-find-ask-widget-design.md` section 6. The spoken track (`docs/superpowers/specs/2026-10-06-lifo-spoken-track-design.md`) is the PR after this one and is not built here; nothing in this plan changes how the voice is produced, only how the screen looks.

## Global Constraints

- Paper is `LifeOSTokens.canvas`, ink is `LifeOSTokens.primaryText`, hairlines are `Editorial.rule(scheme)`, quiet text is `Editorial.quietInk(scheme)`. The accent (`LifeOSTokens.accent`) appears only on the LIFO mark, the waveform and the microphone while listening or speaking, and nowhere else on these screens. No new colours; `CoachScreenStyle.accent`, `.glow`, `.night`, `.card`, `.cell`, `.cardAccent` and `LifoPalette` are deleted, not moved.
- Both screens follow the system colour scheme: no `preferredColorScheme(.dark)` anywhere in `LIfeOS/Features/Coach` or `LIfeOS/Features/Assistant` when this PR ends.
- No gradient field on either screen. Every button uses `.buttonStyle(.editorial(role))` or is a bare glyph with `.buttonStyle(.plain)` and an accessibility label. Every card is `editorialCard()`.
- Fonts come only from `LifeOSType` or `Editorial.figure(_:)` / `Editorial.headline(_:)`. `scripts/check-typography.sh` flags `.system(size:` literals, `design: .rounded`, and Apple's semantic styles such as `.font(.caption)`, `.font(.title3)`, `.font(.body.bold())`; the rewritten files must carry none, so the baseline count drops rather than rises.
- Nothing about what the coach or the assistant sends, stores, or speaks changes: `CoachViewModel.send`, `AssistantViewModel.send`, the tools, the brokers and `SpokenReply` are untouched except for the `#if DEBUG` preview hooks named in Task 5.
- `LifeOSKit` also builds for macOS (`swift test` runs there): the new `DesignSystem` views use nothing iOS-only; `UIApplication.openSettingsURLString` stays in the app target.
- `LIfeOS/` is a synchronized folder in the Xcode project: new, renamed and deleted files under it need no `project.pbxproj` edit.
- PR #18 (`feat/lifo-mark`) adds `LifeOSMark.symbol = "circle.hexagongrid.fill"` in `DesignSystem` and is unmerged. This plan uses that symbol name through one file-private constant in `LifoCoachScreen.swift` with a comment naming #18, so neither PR depends on the other; when #18 merges, a one-line swap to `LifeOSMark.symbol` follows. If #18 has merged by Task 4, use `LifeOSMark.symbol` directly and skip the constant.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution of any kind.
- Work happens in the existing worktree `.claude/worktrees/editorial-coach` on branch `feat/editorial-coach`, cut from `origin/feat/editorial-calendar` at `b4a92eb` (PR #21). `Config/Secrets.xcconfig` is already copied in. The PR targets `feat/editorial-calendar` until #21 merges, then `main`.
- The simulator for builds and captures is `Editorial iPhone 17`, id `B16BEDD3-51EB-442D-B84B-81EDDB2DF923` (iOS 26.2).

## Review Focus

1. The voice masthead says the right thing in every state, and speaking wins over the phase it coexists with: idle `A moment for you`, listening `I'm listening`, thinking `Connecting the dots…`, and while the reply is being read `Let's talk it through` even though the phase is already `answered`. `VoiceHeadlineTests.titlesByState` and `speakingWinsOverAnswered` in Task 1.
2. The assistant masthead's support line changes with connection, and never tells a connected person to connect: `AssistantHeadlineTests.supportLineFollowsConnection` in Task 1.
3. A reply with a two-column table of six rows or fewer draws metric cells, a wider or longer one draws the hairline table, and a plain sentence draws neither: `CoachResponseTests` already pin the parser; the `coach` capture in Task 7 shows a reply with both table shapes and a numbered list.
4. The composer's send button is disabled with empty or whitespace text and while a turn is in flight, and the text field submits on return: the `coach` and `assistant` captures show the dimmed send circle with an empty field; the Task 7 simulator check types a question and submits it.
5. The empty assistant with no calendar shows `Connect calendar` as the one primary action and no prompt rows; connected and empty shows three prompt rows and no connect button: `assistant-empty` and `assistant-empty --connected` captures in Task 7.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/VoiceHeadline.swift` (new) | Voice masthead wording by state; `AssistantHeadline` wording by connection |
| `LifeOSKit/Tests/DesignSystemTests/VoiceHeadlineTests.swift` (new) | Their tests |
| `LifeOSKit/Sources/DesignSystem/Chat.swift` (new) | `ChatQuestion`, `ChatTurn`, `ChatThinking`, `ChatComposer`, `ChatConfirmation`, `ChatToolTags`, `WrapLayout` |
| `LifeOSKit/Sources/DesignSystem/AudioWaveform.swift` (new) | The ink waveform, moved from the coach screen and made public |
| `LIfeOS/Features/Coach/View/CoachResponseView.swift` | Blocks on paper: paragraphs, headings, numbered steps with `IndexPill`, metric cells, hairline tables |
| `LIfeOS/Features/Coach/View/LifoCoachScreen.swift` | The coach on paper: header, opening, transcript, composer, voice screen, controls, history; `CoachScreenStyle` |
| `LIfeOS/Features/Coach/View/LifoAura.swift` (deleted) | Aura, palette and the coloured style |
| `LIfeOS/Features/Coach/View/CoachVoiceOrb.swift` (deleted) | The orb |
| `LIfeOS/Features/Assistant/View/AssistantSheet.swift` | The assistant on paper |
| `LIfeOS/Features/Assistant/View/AssistantAgendaCard.swift` | The agenda card on paper |
| `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift` | `#if DEBUG` preview hooks only |
| `LIfeOS/Features/Coach/View/CoachDesignPreview.swift` | Pages `coach`, `coach-empty`, `coach-voice` |
| `LIfeOS/Features/Assistant/View/AssistantDesignPreview.swift` (new, DEBUG) | Pages `assistant`, `assistant-empty` (`--connected`) |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Routes those pages |

---

### Task 0: Worktree and the typography baseline

- [ ] **Step 1: Confirm the worktree**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-coach
git status --short && git log --oneline -1 && ls Config/Secrets.xcconfig
```

Expected: a clean tree at `b4a92eb fix(calendar): scroll to the masthead...` (or a later commit of `feat/editorial-calendar` if #21 gained commits; then `git fetch origin && git rebase origin/feat/editorial-calendar` first) and the secrets file present.

- [ ] **Step 2: Record the typography baseline**

```bash
scripts/check-typography.sh > /tmp/typo-coach-base.txt 2>&1; echo "baseline lines: $(wc -l < /tmp/typo-coach-base.txt)"
grep -c "Features/Coach\|Features/Assistant" /tmp/typo-coach-base.txt
```

Expected: a line count, and a second count of the violations inside the two folders this PR rewrites. The second number must be zero at Task 7.

---

### Task 1: `VoiceHeadline` and `AssistantHeadline`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/VoiceHeadline.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/VoiceHeadlineTests.swift`

**Interfaces:**
- Produces: `public enum VoiceState: Hashable, Sendable { case idle, listening, thinking, speaking }`; `public struct VoiceHeadline { eyebrow: String; title: String; detail: String; static func make(_ state: VoiceState) -> VoiceHeadline }`; `public struct AssistantHeadline { eyebrow: String; title: String; detail: String; static func make(connected: Bool) -> AssistantHeadline }`. Task 4 maps the coach's phase and speaking flag to a `VoiceState`; Task 5 uses `AssistantHeadline`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import DesignSystem

@Suite struct VoiceHeadlineTests {
    @Test func titlesByState() {
        #expect(VoiceHeadline.make(.idle).title == "A moment for you")
        #expect(VoiceHeadline.make(.idle).detail == "Tap the microphone whenever you're ready.")
        #expect(VoiceHeadline.make(.listening).title == "I'm listening")
        #expect(VoiceHeadline.make(.listening).detail == "Speak naturally. I'll follow along.")
        #expect(VoiceHeadline.make(.thinking).title == "Connecting the dots…")
        #expect(VoiceHeadline.make(.thinking).detail == "Making sense of your question.")
        #expect(VoiceHeadline.make(.speaking).title == "Let's talk it through")
        #expect(VoiceHeadline.make(.speaking).detail == "Your answer is here to read, too.")
        #expect(VoiceHeadline.make(.idle).eyebrow == "Voice conversation")
    }

    @Test func speakingWinsOverAnswered() {
        // The screen maps its phase and its player to one state; the player
        // speaking is the state that matters, whatever the phase says.
        #expect(VoiceState.from(isListening: false, isThinking: false, isSpeaking: true) == .speaking)
        #expect(VoiceState.from(isListening: true, isThinking: false, isSpeaking: false) == .listening)
        #expect(VoiceState.from(isListening: false, isThinking: true, isSpeaking: false) == .thinking)
        #expect(VoiceState.from(isListening: false, isThinking: false, isSpeaking: false) == .idle)
    }
}

@Suite struct AssistantHeadlineTests {
    @Test func supportLineFollowsConnection() {
        let connected = AssistantHeadline.make(connected: true)
        #expect(connected.eyebrow == "Calendar assistant")
        #expect(connected.title == "Make room for your day")
        #expect(connected.detail == "Ask about your schedule, or tell me to move something.")
        let not = AssistantHeadline.make(connected: false)
        #expect(not.detail == "Connect your calendar so I can see your schedule.")
        #expect(!not.detail.isEmpty && not.detail != connected.detail)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter "VoiceHeadlineTests|AssistantHeadlineTests"`
Expected: compile errors, `cannot find 'VoiceHeadline' in scope`.

- [ ] **Step 3: Write the values**

```swift
import Foundation

/// What the voice screen is doing, as one state. The screen has a phase
/// and a player that can both be true at once (the phase is `answered`
/// while the reply is still being read); this collapses them in the order
/// that matters to the person listening.
public enum VoiceState: Hashable, Sendable {
    case idle, listening, thinking, speaking

    public static func from(isListening: Bool, isThinking: Bool, isSpeaking: Bool) -> VoiceState {
        if isSpeaking { return .speaking }
        if isListening { return .listening }
        if isThinking { return .thinking }
        return .idle
    }
}

/// The voice screen's masthead by state. A value so the wording is tested.
public struct VoiceHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String

    public init(eyebrow: String, title: String, detail: String) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    public static func make(_ state: VoiceState) -> VoiceHeadline {
        let eyebrow = "Voice conversation"
        switch state {
        case .idle:
            return VoiceHeadline(eyebrow: eyebrow, title: "A moment for you",
                                 detail: "Tap the microphone whenever you're ready.")
        case .listening:
            return VoiceHeadline(eyebrow: eyebrow, title: "I'm listening",
                                 detail: "Speak naturally. I'll follow along.")
        case .thinking:
            return VoiceHeadline(eyebrow: eyebrow, title: "Connecting the dots…",
                                 detail: "Making sense of your question.")
        case .speaking:
            return VoiceHeadline(eyebrow: eyebrow, title: "Let's talk it through",
                                 detail: "Your answer is here to read, too.")
        }
    }
}

/// The calendar assistant's masthead. The support line is the one piece
/// that changes: it must never tell a connected person to connect.
public struct AssistantHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String

    public init(eyebrow: String, title: String, detail: String) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    public static func make(connected: Bool) -> AssistantHeadline {
        AssistantHeadline(
            eyebrow: "Calendar assistant",
            title: "Make room for your day",
            detail: connected
                ? "Ask about your schedule, or tell me to move something."
                : "Connect your calendar so I can see your schedule."
        )
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `cd LifeOSKit && swift test --filter "VoiceHeadlineTests|AssistantHeadlineTests"`
Expected: `3 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/VoiceHeadline.swift LifeOSKit/Tests/DesignSystemTests/VoiceHeadlineTests.swift
git commit -m "feat(design): the voice and assistant mastheads as tested values

VoiceState collapses the coach's phase and player into one state, with
speaking first; VoiceHeadline and AssistantHeadline own the wording."
```

---

### Task 2: The shared chat pieces and the waveform

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/Chat.swift`
- Create: `LifeOSKit/Sources/DesignSystem/AudioWaveform.swift`

**Interfaces:**
- Consumes: `Editorial`, `EditorialTag`, `Hairline`, `Space`, `Radius`, `LifeOSType`, `LifeOSTokens`, `.editorial(role)`.
- Produces, all public:
  - `ChatQuestion(_ text: String)`: the question in ink inside a hairline-outlined block, aligned trailing.
  - `ChatTurn(question: String?) { reply }`: the question (when not empty) over any reply view.
  - `ChatThinking()`: `Thinking…` in quiet ink.
  - `ChatComposer(text: Binding<String>, placeholder: String, isSending: Bool, focus: FocusState<Bool>.Binding? = nil, onSend: @escaping () -> Void) { accessory }` and the accessory-free init; the send button is an ink circle with `arrow.up` in paper, disabled when the trimmed text is empty or `isSending`.
  - `ChatConfirmation(lines: [String], onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void)`: an `editorialCard()` with the lines over `Confirm` (`.editorial(.primary, size: .compact)`) and `Cancel` (`.editorial(.secondary, size: .compact)`).
  - `ChatToolTags(_ summaries: [String])`: `EditorialTag`s in a `WrapLayout`.
  - `WrapLayout(spacing: CGFloat = Space.x1)`: a `Layout` that wraps its subviews onto new rows.
  - `AudioWaveform(level: CGFloat, active: Bool, color: Color)`: the rolling amplitude history, 48 bars, silent at rest.

There are no unit tests for these views; the package has none for views, and Task 7's captures are their check. The tested wording sits in Task 1.

- [ ] **Step 1: Write `Chat.swift`**

```swift
import SwiftUI

/// The pieces a conversation on paper is made of, shared by LIFO and the
/// calendar assistant so the two screens cannot drift apart.

/// The person's question: ink inside a hairline-outlined block, aligned
/// trailing. A transcript entry, not the loudest thing on the screen.
public struct ChatQuestion: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(LifeOSType.secondary)
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Editorial.rule(scheme)))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// One exchange: the question over the reply. A nil or empty question draws
/// no block, which is how a nudge LIFO opened with reads.
public struct ChatTurn<Reply: View>: View {
    let question: String?
    let reply: Reply
    public init(question: String?, @ViewBuilder reply: () -> Reply) {
        self.question = question; self.reply = reply()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if let question, !question.isEmpty { ChatQuestion(question) }
            reply
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line that holds the place of a reply still being written.
public struct ChatThinking: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        Text("Thinking…")
            .font(LifeOSType.secondary)
            .foregroundStyle(Editorial.quietInk(scheme))
            .accessibilityLabel("Thinking")
    }
}

/// The composer: a hairline-outlined bar with the field and an ink send
/// circle, and room for one accessory beside it (LIFO's voice toggle).
public struct ChatComposer<Accessory: View>: View {
    @Binding var text: String
    let placeholder: String
    let isSending: Bool
    let focus: FocusState<Bool>.Binding?
    let onSend: () -> Void
    let accessory: Accessory
    @Environment(\.colorScheme) private var scheme

    public init(text: Binding<String>, placeholder: String, isSending: Bool,
                focus: FocusState<Bool>.Binding? = nil,
                onSend: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory) {
        _text = text; self.placeholder = placeholder; self.isSending = isSending
        self.focus = focus; self.onSend = onSend; self.accessory = accessory()
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        let ink = LifeOSTokens.primaryText.resolve(scheme)
        let paper = LifeOSTokens.canvas.resolve(scheme)
        HStack(alignment: .bottom, spacing: Space.x1) {
            HStack(alignment: .bottom, spacing: Space.x1) {
                field
                    .font(LifeOSType.secondary)
                    .foregroundStyle(ink)
                    .lineLimit(1...4)
                    .padding(.vertical, 10)
                    .onSubmit { if canSend { onSend() } }
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(paper)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ink))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.38)
                .accessibilityLabel("Send")
                .padding(.bottom, Space.half)
            }
            .padding(.leading, Space.x2)
            .padding(.trailing, Space.half)
            .padding(.vertical, Space.half)
            .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(Editorial.rule(scheme)))
            accessory
        }
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField(placeholder, text: $text, axis: .vertical).focused(focus)
        } else {
            TextField(placeholder, text: $text, axis: .vertical)
        }
    }
}

extension ChatComposer where Accessory == EmptyView {
    public init(text: Binding<String>, placeholder: String, isSending: Bool,
                focus: FocusState<Bool>.Binding? = nil, onSend: @escaping () -> Void) {
        self.init(text: text, placeholder: placeholder, isSending: isSending,
                  focus: focus, onSend: onSend) { EmptyView() }
    }
}

/// A write the assistant wants to make, awaiting a yes or a no.
public struct ChatConfirmation: View {
    let lines: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(lines: [String], onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.lines = lines; self.onConfirm = onConfirm; self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: Space.half) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.x1) {
                Button("Confirm", action: onConfirm).buttonStyle(.editorial(.primary, size: .compact))
                Button("Cancel", action: onCancel).buttonStyle(.editorial(.secondary, size: .compact))
            }
        }
        .editorialCard()
    }
}

/// What a reply did, as tags: `Checked your calendar`, `Created an event`.
public struct ChatToolTags: View {
    let summaries: [String]
    public init(_ summaries: [String]) { self.summaries = summaries }
    public var body: some View {
        WrapLayout(spacing: Space.x1) {
            ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                EditorialTag(summary)
            }
        }
    }
}

/// Lays subviews out in rows, wrapping when the width runs out. For tags
/// and pills, which should read as words in a sentence, not as a grid.
public struct WrapLayout: Layout {
    let spacing: CGFloat
    public init(spacing: CGFloat = Space.x1) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
```

- [ ] **Step 2: Write `AudioWaveform.swift`**

The body is `CoachAudioWaveform` from `LifoCoachScreen.swift:419-446`, made public and given a doc comment that says what it is for:

```swift
import SwiftUI

/// A rolling amplitude history from the microphone or a spoken reply,
/// silent at rest. Forty-eight bars in one colour: ink when idle, the
/// accent while LIFO listens or speaks. This is the whole of the voice
/// screen's visual, in place of the orb that used to fill it.
public struct AudioWaveform: View {
    let level: CGFloat
    let active: Bool
    let color: Color
    @State private var samples = Array(repeating: CGFloat.zero, count: 48)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(level: CGFloat, active: Bool, color: Color) {
        self.level = level; self.active = active; self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            for (index, sample) in samples.enumerated() {
                let height = max(2, sample * (size.height - 4))
                let rect = CGRect(x: CGFloat(index) * size.width / 48, y: (size.height - height) / 2,
                                  width: 2, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.35 + sample * 0.65)))
            }
        }
        .onChange(of: level) { _, value in
            guard !reduceMotion else { return }
            samples.removeFirst()
            samples.append(active && value.isFinite ? min(max(value, 0), 1) : 0)
        }
        .onChange(of: active) { _, active in
            if !active { samples = Array(repeating: 0, count: 48) }
        }
        .accessibilityLabel(active ? "Audio is active" : "Audio is idle")
    }
}
```

- [ ] **Step 3: Build the package for both platforms**

```bash
cd LifeOSKit && swift build 2>&1 | grep -E "error:|warning: var|Compiling|Build complete" | tail -3
```

Expected: `Build complete!` and no `error:`.

- [ ] **Step 4: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/Chat.swift LifeOSKit/Sources/DesignSystem/AudioWaveform.swift
git commit -m "feat(design): the chat pieces on paper and the ink waveform

ChatQuestion, ChatTurn, ChatThinking, ChatComposer, ChatConfirmation,
ChatToolTags and WrapLayout, shared by LIFO and the calendar assistant;
AudioWaveform moves out of the coach screen so the orb can go."
```

---

### Task 3: `CoachResponseView` on paper

**Files:**
- Modify: `LIfeOS/Features/Coach/View/CoachResponseView.swift` (whole file)

**Interfaces:**
- Consumes: `CoachResponse` (Insights), `IndexPill`, `Hairline`, `Editorial`, `LifeOSType`.
- Produces: `CoachResponseView(text: String)`. The `onAura` and `style` parameters are removed; Task 4 and Task 5 call the one-argument form.

- [ ] **Step 1: Replace the file**

```swift
import SwiftUI
import Insights
import DesignSystem

/// A reply drawn from its content: a sentence stays a sentence, two metrics
/// become cells, a comparison becomes a hairline table, steps are numbered.
/// On paper, in ink; nothing about it is a card unless it holds a figure.
struct CoachResponseView: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(Array(CoachResponse(text).blocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .modifier(BlockReveal(index: index))
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: CoachResponse.Block) -> some View {
        switch block {
        case .paragraph(let text):
            richText(text)
                .font(LifeOSType.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            richText(text)
                .font(LifeOSType.sectionTitle)
                .padding(.top, Space.half)
                .accessibilityAddTraits(.isHeader)
        case .list(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                        IndexPill(index + 1)
                        richText(item).font(LifeOSType.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    if index < items.count - 1 { Hairline() }
                }
            }
        case .table(let headers, let rows):
            if headers.count == 2 && rows.count <= 6 {
                metricCells(headers: headers, rows: rows)
            } else {
                comparisonTable(headers: headers, rows: rows)
            }
        }
    }

    private func richText(_ value: String) -> Text {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
    }

    /// Two columns, six rows or fewer: each row is a figure with its label
    /// above, on a hairline card, two to a row.
    private func metricCells(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(headers.joined(separator: " · ")).editorialEyebrow()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Space.x1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: Space.half) {
                        richText(row[0]).editorialEyebrow()
                        richText(row[1])
                            .font(Editorial.figure(28)).tracking(Editorial.figureTracking(28))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .editorialCard(padding: Space.x2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Wider or longer: a ruled table. Headers as eyebrows, rows separated
    /// by hairlines, scrolling sideways when the columns do not fit.
    private func comparisonTable(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            richText(header).editorialEyebrow()
                                .frame(minWidth: 92, maxWidth: 160, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal).overlay(Editorial.rule(scheme))
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                                richText(value).font(LifeOSType.secondary)
                                    .frame(minWidth: 92, maxWidth: 160, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 12)
                                    .accessibilityLabel("\(headers[column]): \(value)")
                            }
                        }
                        if index < rows.count - 1 {
                            Divider().gridCellUnsizedAxes(.horizontal).overlay(Editorial.rule(scheme))
                        }
                    }
                }
            }
        }
        .accessibilityHint("Scroll horizontally for additional columns")
    }
}

/// Each block comes up a beat after the one above it.
///
/// The answer is held until the voice starts, then arrives while it is
/// speaking; a screen that fills in one frame under a voice still on its
/// first sentence reads as two things happening, and a screen that fills in
/// step with it reads as one. State lives on the block, so a block already
/// on screen is never re-animated when the text under it streams on.
private struct BlockReveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                let delay = Double(min(index, 5)) * 0.14
                withAnimation(.easeOut(duration: 0.4).delay(delay)) { shown = true }
            }
    }
}

#Preview("Coach · metrics and actions") {
    ScrollView {
        CoachResponseView(text: """
        Your sleep is more consistent this week. Keep the same wake-up time.

        ## This week
        | Metric | Value |
        | --- | --- |
        | Average sleep | 7 h 24 min |
        | Recovery | 72% |

        ## Next step
        - Start winding down 30 minutes before your usual bedtime.
        """)
        .padding(24)
    }
    .background(LifeOSTokens.canvas.light)
}
```

- [ ] **Step 2: Do not build yet**

`LifoCoachScreen.swift` still passes `onAura:` and `style:`; Task 4 replaces it. Move on.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Coach/View/CoachResponseView.swift
git commit -m "feat(coach): draw replies on paper with numbered steps and hairline tables

The aura mode and its colours go; metric cells are hairline cards with a
light figure, comparisons are ruled tables, steps carry index pills. Does
not build alone; the coach screen follows."
```

---

### Task 4: `LifoCoachScreen` on paper, the aura and orb deleted

**Files:**
- Modify: `LIfeOS/Features/Coach/View/LifoCoachScreen.swift` (whole file)
- Delete: `LIfeOS/Features/Coach/View/LifoAura.swift`, `LIfeOS/Features/Coach/View/CoachVoiceOrb.swift`

**Interfaces:**
- Consumes: Task 1's `VoiceState`, `VoiceHeadline`; Task 2's `ChatTurn`, `ChatThinking`, `ChatComposer`, `AudioWaveform`, `WrapLayout`; Task 3's `CoachResponseView(text:)`; `CoachViewModel` as it is (`phase`, `history`, `answer`, `pendingQuestion`, `draft`, `level`, `liveTranscript`, `error`, `needsAppleIntelligence`, `voicePlayer.isSpeaking`, `voicePlayer.level`, `voiceScreenActive`, `appear()`, `disappear()`, `showKeyboard()`, `sendTyped()`, `toggleListening()`, `stopSpeaking()`).
- Produces: `enum CoachScreenStyle: String { case text, voice }` (now defined in this file); `LifoCoachScreen(model:onDismiss:initialMode:)` unchanged in signature, so `RootView` and the preview compile as they are.

- [ ] **Step 1: Confirm nothing else uses what is about to go**

```bash
grep -rn "LifoAura\|CoachVoiceOrb\|LifoPalette\|glassPane\|GlassPane\b\|AnyInsettableShape\|CoachAudioWaveform\|\.night\b\|\.cardAccent\|style\.accent" --include='*.swift' LIfeOS | grep -v "Features/Coach/View/LifoCoachScreen.swift\|Features/Coach/View/LifoAura.swift\|Features/Coach/View/CoachVoiceOrb.swift\|Features/Coach/View/CoachResponseView.swift"
```

Expected: no output. (`GlassPanel` in `WhoopConnectModal` and `TrendChart` is a different type and is not matched by `GlassPane\b`.) If anything prints, stop and record a ruling before deleting.

- [ ] **Step 2: Delete the two files**

```bash
git rm -q LIfeOS/Features/Coach/View/LifoAura.swift LIfeOS/Features/Coach/View/CoachVoiceOrb.swift
```

- [ ] **Step 3: Replace `LifoCoachScreen.swift`**

```swift
import SwiftUI
import UIKit
import DesignSystem
import Insights

/// Which face the coach shows: the typed conversation or the voice one.
/// Two cases and nothing else; the colours it used to carry are gone with
/// the aura. Both faces are paper and ink and follow the system scheme.
enum CoachScreenStyle: String {
    case text, voice
}

/// Two presentations of one conversation. Changing screens never recreates the model.
struct LifoCoachScreen: View {
    @Bindable var model: CoachViewModel
    var onDismiss: () -> Void
    var initialMode: CoachScreenStyle = .text

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @FocusState private var typingFocused: Bool
    @State private var showHistory = false
    @State private var mode: CoachScreenStyle = .text

    /// The LIFO mark. PR #18 names this `LifeOSMark.symbol` in DesignSystem;
    /// until that merges the symbol is spelled here, once, so the two PRs do
    /// not depend on each other. Swap to `LifeOSMark.symbol` after #18.
    private static let markSymbol = "circle.hexagongrid.fill"

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    private var isEmpty: Bool {
        model.history.isEmpty && model.answer.isEmpty && model.pendingQuestion.isEmpty
    }
    private var isSpeaking: Bool { model.voicePlayer.isSpeaking }
    private var activityLevel: CGFloat {
        if model.phase == .listening { return model.level }
        return isSpeaking ? model.voicePlayer.level : 0
    }
    private var voiceState: VoiceState {
        VoiceState.from(isListening: model.phase == .listening,
                        isThinking: model.phase == .thinking,
                        isSpeaking: isSpeaking)
    }
    /// The accent is for what is live: LIFO listening or speaking.
    private var liveColor: Color {
        model.phase == .listening || isSpeaking ? LifeOSTokens.accent : ink
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if mode == .text { textScreen } else { voiceScreen }
        }
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .background(paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if mode == .text { textComposer } else { voiceControls }
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .background(paper)
        }
        .sheet(isPresented: $showHistory) { historySheet }
        .task {
            mode = initialMode
            model.voiceScreenActive = mode == .voice
            model.appear()
        }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appear() } else { model.disappear() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.x2) {
            if mode == .voice {
                glyphButton("chevron.left", label: "Back to text chat") { switchMode(.text) }
            } else {
                Image(systemName: Self.markSymbol)
                    .font(LifeOSType.sectionTitle)
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .text ? "Your personal coach" : "Voice conversation").editorialEyebrow()
                Text("LIFO").font(Editorial.headline(22)).tracking(-0.5).foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if !model.history.isEmpty {
                glyphButton("clock", label: "Conversation history") { showHistory = true }
            }
            glyphButton("xmark", label: "Close coach") { model.disappear(); onDismiss() }
        }
        .padding(.horizontal, Space.x3).padding(.vertical, 12)
    }

    /// A bare glyph in ink: the header's controls and the voice screen's
    /// secondary buttons. 44pt so the target is honest even without a shape.
    private func glyphButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(LifeOSType.body.weight(.medium))
                .foregroundStyle(ink).frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    /// An outlined circle: the keyboard switch, the end-voice button, and
    /// the composer's voice toggle.
    private func outlinedButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(LifeOSType.body.weight(.medium))
                .foregroundStyle(ink).frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(ink.opacity(0.85), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    // MARK: - Text screen

    private var textScreen: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        if isEmpty {
                            opening.frame(minHeight: max(0, geometry.size.height - 40))
                        } else {
                            transcript
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(.horizontal, Space.x3).padding(.top, Space.x2).padding(.bottom, Space.x2)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.pendingQuestion) { _, question in
                    if !question.isEmpty { reader.scrollTo("latest", anchor: .bottom) }
                }
            }
        }
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: 14) {
                Text("A little clarity.\nA better day.")
                    .font(LifeOSType.display.weight(.medium))
                    .tracking(-1).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Make sense of your health, money, and everyday life. One question at a time.")
                    .font(LifeOSType.body).foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.x2)
            Spacer(minLength: Space.x5)
            VStack(alignment: .leading, spacing: 12) {
                Text("Where shall we start?").editorialEyebrow()
                WrapLayout(spacing: Space.x1) { suggestions }
            }
            if let error = model.error { errorView(error) }
        }
    }

    /// Outlined pills that send their question. The pill is `EditorialTag`
    /// wrapped in a button, so it reads as a word, not a card.
    private var suggestions: some View {
        ForEach(Array(Self.prompts.enumerated()), id: \.offset) { _, item in
            Button {
                model.draft = item.question
                Task { await model.sendTyped() }
            } label: {
                EditorialTag(item.title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.question)
            .disabled(model.phase == .thinking)
        }
    }
    private static let prompts = [
        (title: "My sleep", question: "How did I sleep this week?"),
        (title: "My spending", question: "Where did my money go?"),
        (title: "My next step", question: "What should I focus on today?")
    ]

    private var transcript: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            ForEach(model.history) { turn in
                turnView(question: turn.question, answer: turn.answer, sent: turn.sent)
            }

            // The turn in flight. The question is drawn from
            // `pendingQuestion`, which is set the instant it is asked, so it
            // is on screen through the whole wait rather than appearing with
            // the answer it was waiting for.
            if !model.pendingQuestion.isEmpty {
                ChatTurn(question: model.pendingQuestion) {
                    if model.answer.isEmpty {
                        ChatThinking()
                    } else {
                        CoachResponseView(text: model.answer)
                    }
                }
            }

            if let error = model.error { errorView(error) }
        }
    }

    private func turnView(question: String, answer: String, sent: SentContext?) -> some View {
        ChatTurn(question: question) {
            CoachResponseView(text: answer)
            if let sent { sentView(sent) }
        }
    }

    /// What this answer was produced from, closed by default and openable.
    private func sentView(_ sent: SentContext) -> some View {
        DisclosureGroup {
            Text(sent.text)
                .font(LifeOSType.caption)
                .foregroundStyle(quiet)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, Space.x1)
        } label: {
            Label(sent.headline, systemImage: sent.tier == .cloud ? "cloud" : "iphone")
                .font(LifeOSType.caption.weight(.medium))
                .foregroundStyle(quiet)
        }
        .tint(quiet)
        .padding(.top, 2)
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(error)
                .font(LifeOSType.secondary)
                .foregroundStyle(quiet)
                .fixedSize(horizontal: false, vertical: true)
            if model.needsAppleIntelligence {
                Button("Turn on Apple Intelligence") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.editorial(.secondary, size: .compact))
            }
        }
    }

    private var textComposer: some View {
        ChatComposer(text: $model.draft, placeholder: "Ask about your day…",
                     isSending: model.phase == .thinking, focus: $typingFocused,
                     onSend: { Task { await model.sendTyped() } }) {
            outlinedButton("waveform", label: "Open voice conversation") { switchMode(.voice) }
        }
        .padding(.horizontal, Space.x3).padding(.top, 12).padding(.bottom, 12)
    }

    // MARK: - Voice screen

    private var voiceScreen: some View {
        let headline = VoiceHeadline.make(voiceState)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
                    .padding(.top, Space.x2)
                AudioWaveform(level: activityLevel,
                              active: model.phase == .listening || isSpeaking,
                              color: liveColor)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                if model.phase == .listening && !model.liveTranscript.isEmpty {
                    Text(model.liveTranscript).font(LifeOSType.body).foregroundStyle(ink)
                        .textSelection(.enabled)
                }
                if !model.pendingQuestion.isEmpty {
                    ChatTurn(question: model.pendingQuestion) {
                        if !model.answer.isEmpty { CoachResponseView(text: model.answer) }
                    }
                } else if let turn = model.history.last {
                    ChatTurn(question: turn.question) {
                        CoachResponseView(text: turn.answer)
                        if let sent = turn.sent { sentView(sent) }
                    }
                }
                if let error = model.error { errorView(error) }
            }
            .padding(.horizontal, Space.x3).padding(.bottom, Space.x3)
        }
        .scrollIndicators(.hidden)
    }

    private var voiceControls: some View {
        VStack(spacing: Space.x1) {
            HStack(spacing: Space.x5) {
                outlinedButton("keyboard", label: "Switch to text chat") { switchMode(.text) }
                Button {
                    if isSpeaking { model.stopSpeaking() }
                    else { Task { await model.toggleListening() } }
                } label: {
                    Image(systemName: model.phase == .listening || isSpeaking ? "stop.fill" : "mic.fill")
                        .font(LifeOSType.screenTitle.weight(.medium)).foregroundStyle(paper)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(liveColor))
                }
                .buttonStyle(.plain)
                .disabled(model.phase == .thinking)
                .accessibilityLabel(isSpeaking ? "Stop speaking" : model.phase == .listening ? "Finish recording and send" : "Start listening")
                outlinedButton("xmark", label: "End voice conversation") { switchMode(.text) }
            }
            Text(model.phase == .listening ? "Tap to finish" : isSpeaking ? "Tap to stop" : "Tap to speak")
                .font(LifeOSType.caption).foregroundStyle(quiet)
        }
        .padding(.top, Space.x1).padding(.bottom, Space.x2)
    }

    private func switchMode(_ destination: CoachScreenStyle) {
        typingFocused = false
        if destination == .text { model.showKeyboard() }
        model.voiceScreenActive = destination == .voice
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { mode = destination }
    }

    // MARK: - History

    private var historySheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.x3) {
                    ForEach(model.history) { turn in
                        turnView(question: turn.question, answer: turn.answer, sent: turn.sent)
                    }
                }
                .padding(Space.x3)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } } }
        }
        .presentationDetents([.large])
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet > /tmp/build-coach4.log 2>&1; echo "build exit $?"; grep -E "error:" /tmp/build-coach4.log | sed 's|.*/LIfeOS/||' | sort -u | head
```

Expected: `build exit 0`. `CoachDesignPreview.swift` still compiles because the screen's signature is unchanged. If `ChatComposer`'s `focus:` argument does not accept `$typingFocused` (a `FocusState<Bool>.Binding`), the diagnostic names the line; the parameter type in Task 2 is `FocusState<Bool>.Binding?`, which is what `$typingFocused` is.

- [ ] **Step 5: Commit**

```bash
git add -A LIfeOS/Features/Coach/View/LifoCoachScreen.swift LIfeOS/Features/Coach/View/LifoAura.swift LIfeOS/Features/Coach/View/CoachVoiceOrb.swift
git commit -m "feat(coach): LIFO on paper, following the system scheme

Masthead header with the mark and bare glyphs, outlined question blocks,
replies on paper, one shared composer with an outlined voice toggle, and
the ink waveform in place of the orb. LifoAura, CoachVoiceOrb and the LIFO
palette are deleted; CoachScreenStyle keeps its two cases and no colours."
```

---

### Task 5: The assistant sheet and its agenda card on paper

**Files:**
- Modify: `LIfeOS/Features/Assistant/View/AssistantSheet.swift` (whole file)
- Modify: `LIfeOS/Features/Assistant/View/AssistantAgendaCard.swift` (styling only; the `body`, `header`, `strip`, `rows`, `row`, `dottedRule`, `addButton` members)
- Modify: `LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift` (`#if DEBUG` hooks)

**Interfaces:**
- Consumes: Task 1's `AssistantHeadline`; Task 2's `ChatTurn`, `ChatThinking`, `ChatComposer`, `ChatConfirmation`, `ChatToolTags`; Task 3's `CoachResponseView(text:)`; `CalendarScreen` from PR #21; `AssistantViewModel` as it is plus the hooks below.
- Produces: `AssistantSheet(model:)` unchanged in signature; `#if DEBUG` on `AssistantViewModel`: `var previewAuthorized: Bool?` (read in `appear()` instead of EventKit when set) and `func previewSeed(pending: [PendingWrite])` (sets `pending`). Task 6 uses both.

- [ ] **Step 1: The view model hooks**

In `AssistantViewModel.swift`, after `private(set) var isAuthorized = false`, add:

```swift
    #if DEBUG
    /// Design previews run without calendar access; this answers `appear()`
    /// in place of EventKit so the connected state can be drawn.
    var previewAuthorized: Bool?
    /// Design previews need a confirmation card on screen without a model turn.
    func previewSeed(pending writes: [PendingWrite]) { pending = writes }
    #endif
```

And change the one line in `appear()`:

```swift
        isAuthorized = await eventKit.isAuthorized
```

to:

```swift
        #if DEBUG
        isAuthorized = previewAuthorized ?? (await eventKit.isAuthorized)
        #else
        isAuthorized = await eventKit.isAuthorized
        #endif
```

Nothing else in the file changes.

- [ ] **Step 2: Replace `AssistantSheet.swift`**

```swift
import SwiftUI
import DesignSystem
import Insights
import Persistence

/// The calendar assistant: masthead, prompt rows, the conversation, inline
/// confirmation cards, composer. A pure function of the view model's state,
/// on paper, in the same pieces LIFO uses.
struct AssistantSheet: View {
    @State var model: AssistantViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composing: Bool
    /// Raised by a tap on an agenda card's row or its Add. The same sheet
    /// Today uses, so an event edited from a conversation and one edited from
    /// the day view are edited in one place.
    @State private var eventSheet: EventSheetPresentation?

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var paper: Color { LifeOSTokens.canvas.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.modelAvailable {
                    Spacer()
                    Text("The assistant needs Apple Intelligence, which isn't available on this device.")
                        .font(LifeOSType.secondary)
                        .foregroundStyle(quiet)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.x4)
                    Spacer()
                } else {
                    conversation
                    // The empty state carries the connect button, but a
                    // conversation with history hides that state; someone
                    // who revoked access later still needs a way back in.
                    if !model.isAuthorized, !model.messages.isEmpty {
                        HStack(spacing: Space.x1) {
                            Text("Calendar not connected").font(LifeOSType.secondary).foregroundStyle(quiet)
                            Spacer()
                            Button("Connect") { Task { await model.connectCalendar() } }
                                .buttonStyle(.editorial(.secondary, size: .compact))
                        }
                        .padding(.horizontal, Space.x2)
                        .padding(.bottom, Space.half)
                    }
                    ChatComposer(text: Bindable(model).draft, placeholder: "Ask about your calendar…",
                                 isSending: model.isThinking, focus: $composing,
                                 onSend: { Task { await model.send() } })
                        .padding(.horizontal, Space.x2)
                        .padding(.bottom, 12)
                }
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CalendarScreen(onTapEvent: { eventSheet = .edit($0) },
                                       onAddEvent: { eventSheet = .create(on: $0) },
                                       isCalendarConnected: model.isAuthorized,
                                       onConnectCalendar: { Task { await model.connectCalendar() } })
                    } label: { Label("Schedule", systemImage: "calendar") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $eventSheet) { mode in
            EventSheet(
                mode: mode,
                onSave: { draft in
                    let id: UUID? = if case .edit(let event) = mode { event.id } else { nil }
                    Task { await model.save(draft, editing: id) }
                },
                onDelete: {
                    guard case .edit(let event) = mode else { return }
                    Task { await model.delete(id: event.id) }
                }
            )
        }
        .tint(ink)
        .task { await model.appear() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.x3) {
                    masthead
                    if model.messages.isEmpty { emptyState }
                    ForEach(model.messages) { message in
                        bubble(message).id(message.id)
                    }
                    ForEach(model.pending) { write in
                        ChatConfirmation(lines: write.preview,
                                         onConfirm: { model.confirm(write.id) },
                                         onCancel: { model.cancel(write.id) })
                            .id(write.id)
                    }
                    if model.isThinking && model.pending.isEmpty {
                        ChatThinking()
                    }
                }
                .padding(.horizontal, Space.x2)
                .padding(.top, Space.x1)
                .padding(.bottom, Space.x2)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) {
                if let last = model.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: model.pending.count) {
                if let last = model.pending.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var masthead: some View {
        let headline = AssistantHeadline.make(connected: model.isAuthorized)
        return EditorialMasthead(eyebrow: headline.eyebrow, title: headline.title, detail: headline.detail)
    }

    /// Before the first question: the one action when there is no calendar,
    /// three prompt rows when there is.
    @ViewBuilder private var emptyState: some View {
        if !model.isAuthorized {
            Button("Connect calendar") { Task { await model.connectCalendar() } }
                .buttonStyle(.editorial(.primary))
        } else {
            VStack(spacing: 0) {
                ForEach(["What's on my calendar today?", "Find a free hour tomorrow", "Show my schedule for this week"], id: \.self) { prompt in
                    Button { model.draft = prompt; composing = true } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: Space.x1) {
                                Text(prompt).font(LifeOSType.secondary).foregroundStyle(ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: Space.x1)
                                Image(systemName: "arrow.up.left").font(LifeOSType.caption.weight(.semibold))
                                    .foregroundStyle(quiet)
                            }
                            .padding(.vertical, 14)
                            Hairline()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Puts this question in the composer")
                }
            }
        }
    }

    /// The most recent thing the assistant said. It always carries an agenda
    /// card, even when the turn called no tool: a reply about the schedule
    /// that draws no schedule is the text-only answer this screen was
    /// changed to stop producing. Older replies keep a card only if they
    /// actually touched events.
    private var latestAssistantID: UUID? {
        model.messages.last { $0.role == .assistant }?.id
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessageSnapshot) -> some View {
        switch message.role {
        case .user: ChatQuestion(message.text)
        default: assistantReply(message)
        }
    }

    private func assistantReply(_ message: ChatMessageSnapshot) -> some View {
        let touched = model.eventsByMessage[message.id] ?? []
        let drawsAgenda = model.isAuthorized
            && (!touched.isEmpty || message.id == latestAssistantID)

        return VStack(alignment: .leading, spacing: Space.x1) {
            CoachResponseView(text: message.text)
            if drawsAgenda {
                AssistantAgendaCard(
                    touched: touched,
                    events: { model.events(on: $0) },
                    onTapEvent: { eventSheet = .edit($0) },
                    onAddEvent: { eventSheet = .create(on: $0) }
                )
            }
            if !message.toolSummaries.isEmpty {
                ChatToolTags(message.toolSummaries)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Restyle `AssistantAgendaCard.swift`**

Replace these members; the model, `init`, `week`, `touchedDays` and `day` stay as they are. The card is an `editorialCard()`; the strip's selected day is an ink-filled square with paper text; the rules are hairlines; the plus becomes an `Add` button.

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            strip.padding(.top, 12)
            rows.padding(.top, 4)
            addButton
        }
        .editorialCard()
    }

    // MARK: - Header

    /// Weekday large on the left, the date stacked small on the right. The
    /// filled accent dot beside the weekday says this is today; a hollow one
    /// says it is another day.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Text(selection.formatted(.dateTime.weekday(.wide)))
                    .font(LifeOSType.sectionTitle)
                    .foregroundStyle(primary)
                Circle()
                    .strokeBorder(LifeOSTokens.accent, lineWidth: 2)
                    .background(Circle().fill(calendar.isDateInToday(selection) ? LifeOSTokens.accent : .clear))
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 8)
            Text(selection.formatted(.dateTime.month(.abbreviated).day().year())).editorialEyebrow()
        }
    }

    // MARK: - Week strip

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selection)
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.day()))
                        .font(LifeOSType.label.weight(isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? LifeOSTokens.canvas.resolve(scheme) : primary)
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(LifeOSType.caption)
                        .foregroundStyle(isSelected ? LifeOSTokens.canvas.resolve(scheme).opacity(0.8) : secondary)
                    // Always laid out, coloured only when the day carries an
                    // event from this reply, so columns never shift.
                    Circle()
                        .fill(touchedDays.contains(calendar.startOfDay(for: date))
                              ? (isSelected ? LifeOSTokens.canvas.resolve(scheme) : LifeOSTokens.accent) : .clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background { if isSelected { Rectangle().fill(primary) } }
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) { selection = calendar.startOfDay(for: date) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .overlay(Rectangle().strokeBorder(Editorial.rule(scheme)))
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        let events = day
        if events.isEmpty {
            HStack {
                Text("Nothing scheduled.").font(LifeOSType.secondary).foregroundStyle(secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 0) {
                ForEach(events) { event in
                    row(event)
                    Hairline()
                }
            }
        }
    }

    /// A row is a time, a title and an arrow, with nothing between them but
    /// space. Past events recede rather than disappear.
    private func row(_ event: CalendarEventSnapshot) -> some View {
        let isPast = event.endDate < .now
        return Button { onTapEvent(event) } label: {
            HStack(spacing: Space.x2) {
                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(LifeOSType.secondary).foregroundStyle(secondary).monospacedDigit()
                    .frame(width: 72, alignment: .leading)
                Text(event.title).font(LifeOSType.secondary.weight(.medium)).foregroundStyle(primary).lineLimit(1)
                Spacer(minLength: Space.x1)
                Image(systemName: "arrow.right").font(LifeOSType.caption.weight(.semibold)).foregroundStyle(primary)
            }
            .padding(.vertical, 12)
            .opacity(isPast ? 0.42 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.spanLabel)")
    }

    /// Creates on the day being looked at, not on today.
    private var addButton: some View {
        Button("Add") { onAddEvent(selection) }
            .buttonStyle(.editorial(.secondary, size: .compact))
            .padding(.top, Space.x2)
            .accessibilityLabel("Add an event on \(selection.formatted(.dateTime.month().day()))")
    }
```

Then delete the `dottedRule` member and the `private struct Line: Shape` at the foot of the file, and the `DayPart` glyph import if the compiler reports it unused (`DayPart` is still used by `AgendaCard`, so the type stays; only this file's use of it goes). Update the card's doc comment's last paragraph to say the card is on paper with hairlines.

- [ ] **Step 4: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet > /tmp/build-coach5.log 2>&1; echo "build exit $?"; grep -E "error:" /tmp/build-coach5.log | sed 's|.*/LIfeOS/||' | sort -u | head
grep -rn "preferredColorScheme\|LifoPalette\|onAura\|\.ultraThinMaterial" --include='*.swift' LIfeOS/Features/Coach LIfeOS/Features/Assistant || echo "no dark forcing, palette, aura or material left"
```

Expected: `build exit 0` and the `no dark forcing...` line.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Assistant/View/AssistantSheet.swift LIfeOS/Features/Assistant/View/AssistantAgendaCard.swift LIfeOS/Features/Assistant/ViewModel/AssistantViewModel.swift
git commit -m "feat(assistant): the calendar assistant on paper

Masthead with the connection sentence, prompt rows with hairlines, the
shared question blocks, composer, confirmation card and tool tags, and
the agenda card as a hairline card with an ink-filled day. DEBUG preview
hooks on the view model for the connected state."
```

---

### Task 6: Preview pages and routing

**Files:**
- Modify: `LIfeOS/Features/Coach/View/CoachDesignPreview.swift` (whole file)
- Create: `LIfeOS/Features/Assistant/View/AssistantDesignPreview.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` (one routing line)

**Interfaces:**
- Consumes: `LifoCoachScreen(model:onDismiss:initialMode:)`, `CoachViewModel` (settable `history`, `phase`, `level`), `AssistantSheet(model:)`, `AssistantViewModel(context:)` with the Task 5 hooks, `ChatStore.append(conversationID:role:text:toolSummaries:eventIDs:)`, `CalendarStore.apply(_:window:)`, `LifeOSContainer.make(inMemory:)`.
- Produces: pages `coach`, `coach-empty`, `coach-voice`, `assistant`, `assistant-empty` (with `--connected`), each honouring `--dark` through the existing mount.

- [ ] **Step 1: Replace `CoachDesignPreview.swift`**

```swift
#if DEBUG
import SwiftUI
import DesignSystem

/// Fixture pages for LIFO, mounted by `--design-preview` with `--page=coach`
/// (a reply with cells, a table and steps), `coach-empty` (the opening) or
/// `coach-voice` (the voice screen, listening, with a simulated level).
/// Audio levels are simulated; no microphone or provider calls.
struct CoachDesignPreview: View {
    let page: String
    @State private var model = CoachViewModel()

    var body: some View {
        LifoCoachScreen(model: model, onDismiss: {}, initialMode: page == "coach-voice" ? .voice : .text)
            .task {
                if page != "coach-empty" {
                    model.history = [LifoTurn(question: "Give me a quick look at my week.", answer: Self.sample)]
                }
                if page == "coach-voice" { await animateListening() }
            }
    }

    private func animateListening() async {
        model.phase = .listening
        var time: Double = 0
        while !Task.isCancelled {
            let syllable = sin(time * 3.6) * 0.6
            let detail = sin(time * 8.0) * 0.2
            model.level = CGFloat(max(0.0, syllable + detail))
            time += 0.08
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    static let sample = """
    Your week, at a glance. Here are the numbers you've recorded.

    | Metric | This week |
    | --- | --- |
    | Average sleep | 7h 24m |
    | Recovery | 72% |

    ## Compared with last week
    | Measure | Last week | This week |
    | --- | --- | --- |
    | Steps / day | 7,420 | 8,610 |
    | Sleep | 7h 02m | 7h 24m |

    ## Next up
    - Review your latest sleep entries.
    - Pick one priority for tomorrow.
    """
}
#endif
```

- [ ] **Step 2: Write `AssistantDesignPreview.swift`**

```swift
#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Insights
import Persistence

/// Fixture pages for the calendar assistant, mounted by `--design-preview`
/// with `--page=assistant` (a conversation with an agenda card, tool tags
/// and a pending confirmation) or `assistant-empty` (the opening; add
/// `--connected` for the prompt rows instead of the connect button).
struct AssistantDesignPreview: View {
    let page: String
    @State private var fixture = AssistantFixture()

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                AssistantSheet(model: page == "assistant-empty" ? fixture.empty : fixture.full)
                    .interactiveDismissDisabled()
            }
            .modelContainer(fixture.container)
    }
}

@MainActor private final class AssistantFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let full: AssistantViewModel
    let empty: AssistantViewModel

    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minutes: Int, _ title: String) -> CalendarEventSnapshot {
            let start = calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: dayOffset, to: today)!)!
            return CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: title, calendarTitle: "Work", title: title,
                                         startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60),
                                         isAllDay: false, isRecurring: false, location: nil, notes: nil)
        }
        let events = [at(0, 9, 30, "Standup"), at(0, 12, 60, "Lunch with Sam"), at(0, 16, 90, "Design review"), at(1, 10, 60, "Dentist")]
        let window = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: today)!,
                                  end: calendar.date(byAdding: .day, value: 14, to: today)!)
        try! CalendarStore(context: container.mainContext, calendar: calendar).apply(events, window: window)

        full = AssistantViewModel(context: container.mainContext)
        full.previewAuthorized = true
        // The same conversation id the model will load, so the seeded turns
        // are the ones it shows.
        let id = UUID()
        UserDefaults.currentAccount.set(id.uuidString, forKey: "assistant.conversationID")
        let chat = ChatStore(context: container.mainContext)
        try! chat.append(conversationID: id, role: .user, text: "What's on my calendar today?")
        try! chat.append(conversationID: id, role: .assistant,
                         text: "Three things today: standup at 9, lunch with Sam at 12, and a design review at 4.",
                         toolSummaries: ["Checked your calendar"], eventIDs: events.prefix(3).map(\.id))
        try! chat.append(conversationID: id, role: .user, text: "Move the design review to 5.")
        full.previewSeed(pending: [PendingWrite(toolName: "update_event",
                                                preview: ["Now: 16:00 to 17:30 | Design review",
                                                          "Becomes: Design review, 17:00 to 18:30"])])

        empty = AssistantViewModel(context: container.mainContext)
        empty.previewAuthorized = ProcessInfo.processInfo.arguments.contains("--connected")
    }
}
#endif
```

Check the exact member names against `ChatStore.append` and `PendingWrite.init` before building; both are quoted from the current sources (`ChatStore.swift`, `ToolGate.swift`). If `UserDefaults.currentAccount` is not reachable from the app target's DEBUG code, it is, since `AssistantViewModel` uses it in the same target.

- [ ] **Step 3: Route the pages**

In `HealthActivityDesignPreview.swift`, after the line that routes the Today pages, add:

```swift
            else if ["coach", "coach-empty", "coach-voice"].contains(page) { CoachDesignPreview(page: page) }
            else if ["assistant", "assistant-empty"].contains(page) { AssistantDesignPreview(page: page) }
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B16BEDD3-51EB-442D-B84B-81EDDB2DF923' -quiet > /tmp/build-coach6.log 2>&1; echo "build exit $?"; grep -E "error:" /tmp/build-coach6.log | sed 's|.*/LIfeOS/||' | sort -u | head
```

Expected: `build exit 0`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Coach/View/CoachDesignPreview.swift LIfeOS/Features/Assistant/View/AssistantDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(coach): design-preview pages for LIFO and the calendar assistant"
```

---

### Task 7: Captures and gates

- [ ] **Step 1: Install and capture**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/editorial-coach
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/editorial-coach/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=B16BEDD3-51EB-442D-B84B-81EDDB2DF923
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/2742294b-e1ce-435a-8249-500b00fd3085/scratchpad
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
capture() { local name=$1; shift
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot "$OUT/pr-coach-$name.png" >/dev/null; }
capture coach --page=coach
capture coach-dark --page=coach --dark
capture coach-empty --page=coach-empty
capture coach-voice --page=coach-voice
capture coach-voice-dark --page=coach-voice --dark
capture assistant --page=assistant
capture assistant-dark --page=assistant --dark
capture assistant-empty --page=assistant-empty
capture assistant-empty-connected --page=assistant-empty --connected
ls -la $OUT/pr-coach-*.png
```

- [ ] **Step 2: Review each against the spec**

- `coach`: paper; the mark in the accent beside `LIFO` with the `YOUR PERSONAL COACH` eyebrow; `clock` and `xmark` bare glyphs; the question in a hairline-outlined block on the right; the reply as a sentence, an eyebrow `METRIC · THIS WEEK` over two hairline cells with light figures, a `COMPARED WITH LAST WEEK` heading over a ruled three-column table, `NEXT UP` over two rows with `01.` and `02.` pills; the composer outlined with a dimmed send circle and the outlined waveform toggle beside it. No colour but the mark.
- `coach-empty`: the two display lines in ink, the quiet sentence, `WHERE SHALL WE START?` and three outlined pills that wrap on one or two rows.
- `coach-voice`: masthead `VOICE CONVERSATION` / `I'm listening` / `Speak naturally. I'll follow along.`; the waveform in the accent; the last turn below; the mic as an accent circle with `stop.fill`, outlined keyboard and close circles, `Tap to finish`.
- `assistant`: masthead `CALENDAR ASSISTANT` / `Make room for your day` / `Ask about your schedule, or tell me to move something.`; a question block; the reply sentence; the agenda card as a hairline card with the ink-filled selected day and three rows with arrows and an `Add` button; a `Checked your calendar` tag; a second question block; the confirmation card with two lines, `Confirm` ink capsule and `Cancel` outlined; the composer.
- `assistant-empty`: masthead with `Connect your calendar so I can see your schedule.` and one `Connect calendar` ink capsule, no prompt rows.
- `assistant-empty-connected`: the connected sentence and three prompt rows with `arrow.up.left`, no connect button.
- Dark variants: paper near black, ink near white, the mark and the waveform still accent, hairlines visible, no light boxes.

Fix anything off in the owning file, commit with a `fix(coach): ...` or `fix(assistant): ...` message, and repeat the capture.

- [ ] **Step 3: One typed question**

On the `coach-empty` page, type a question and submit it, following the simulator memory (Simulator frontmost, AXGroup geometry, `cliclick`):

```bash
capture coach-typed-before --page=coach-empty
# Tap the composer field (bottom bar, left half), then:
# cliclick t:"How did I sleep this week?" then cliclick kp:enter
# Then screenshot to $OUT/pr-coach-typed-after.png
```

Expected: the question appears in a hairline block on the right with `Thinking…` or an error line under it (no model in the preview is fine; the point is the submit path). Two attempts at most; if taps do not land, record it and rely on the captures.

- [ ] **Step 4: Gates**

```bash
(cd LifeOSKit && swift test 2>&1 | tail -2)
scripts/check-typography.sh > /tmp/typo-coach.txt 2>&1
echo "coach/assistant violations now: $(grep -c "Features/Coach\|Features/Assistant" /tmp/typo-coach.txt)"
diff <(sed 's/^[^:]*://' /tmp/typo-coach-base.txt | sort) <(sed 's/^[^:]*://' /tmp/typo-coach.txt | sort) | grep '^>' || echo "typography: no new violations"
```

Expected: the suite passes; `coach/assistant violations now: 0`; `typography: no new violations`.

---

### Task 8: Open the pull request

- [ ] **Step 1: Rebase and push**

```bash
git fetch origin
if git merge-base --is-ancestor origin/feat/editorial-calendar origin/main; then BASE=main; git rebase origin/main; else BASE=feat/editorial-calendar; git rebase origin/feat/editorial-calendar; fi
echo "base: $BASE"
git push -u origin feat/editorial-coach
```

If #18 has merged into the base by now, the rebase conflicts in `LifoCoachScreen.swift` and `CoachResponseView.swift`: take this branch's versions of both, replace `Self.markSymbol` with `LifeOSMark.symbol` and delete the constant, rerun the Task 6 build, and continue.

- [ ] **Step 2: Open the PR** (base as printed; no attribution footer)

```bash
gh pr create --base $BASE --head feat/editorial-coach \
  --title "feat(coach): LIFO and the calendar assistant on the editorial theme" \
  --body "$(cat <<'EOF'
## Summary

- LIFO on paper, following the system colour scheme: a masthead header with the LIFO mark and bare glyphs, the opening as two display lines with outlined prompt pills, questions in hairline-outlined blocks, replies on paper with hairline metric cells, ruled tables and index-pill steps, and one shared composer with an outlined voice toggle. The voice screen is a masthead over an ink waveform that turns accent while LIFO listens or speaks; the microphone is an ink circle that does the same.
- The calendar assistant on the same pieces: masthead with the connection sentence, prompt rows, the shared question blocks, composer, confirmation card and tool tags, and the agenda card as a hairline card.
- Deleted: `LifoAura`, `CoachVoiceOrb`, `LifoPalette`, the glass pane and the coloured `CoachScreenStyle`. New in the design system: `ChatQuestion`, `ChatTurn`, `ChatThinking`, `ChatComposer`, `ChatConfirmation`, `ChatToolTags`, `WrapLayout`, `AudioWaveform`, and the tested `VoiceHeadline` and `AssistantHeadline`.
- Spec: docs/superpowers/specs/2026-10-05-editorial-shell-life-today-notes-coach-guide-design.md section 5 (PR 2 of the order in the calendar spec). Plan: docs/superpowers/plans/2026-10-06-editorial-coach.md.
- The LIFO mark's symbol is spelled once in the coach screen until PR #18 lands `LifeOSMark.symbol`.

## Verification

- LifeOSKit `swift test`: all suites pass, including `VoiceHeadlineTests` and `AssistantHeadlineTests`.
- `scripts/check-typography.sh`: zero violations left in the Coach and Assistant folders; no new violations elsewhere.
- Simulator design-preview pages `coach`, `coach-empty`, `coach-voice`, `assistant`, `assistant-empty` (and `--connected`), light and dark, reviewed against the spec.
EOF
)"
```

- [ ] **Step 3: Report** the PR link, the capture paths, the merge command, and that the spoken track (`feat/lifo-spoken-track`) is next and needs its plan from `docs/superpowers/specs/2026-10-06-lifo-spoken-track-design.md`.
