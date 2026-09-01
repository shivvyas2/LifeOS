import SwiftUI
import UIKit
import DesignSystem
import Insights

/// The coach. Text first, voice second.
///
/// It was voice-first, with a 240pt globe holding the top of the screen and a
/// keyboard tucked behind a button. That inverted the actual usage: most
/// questions are typed, most of the time, and a screen that opens on a
/// microphone asks someone to speak out loud before it asks them anything
/// else. Now the field is the subject of the screen and the mic sits beside
/// it, one tap away, for when speaking is easier.
struct LifoCoachScreen: View {
    @Bindable var model: CoachViewModel
    var onDismiss: () -> Void

    /// The aura is dark in both appearances, so every token here resolves
    /// dark regardless of the system scheme.
    private let scheme: ColorScheme = .dark
    @Environment(\.openURL) private var openURL
    @FocusState private var typingFocused: Bool
    @State private var showHistory = false

    var body: some View {
        ZStack {
            LifoAura(intensity: model.level,
                     isActive: model.phase == .listening || model.phase == .thinking)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // The globe is the listening body, and it appears only
                        // while listening. Standing it at the top of a resting
                        // screen was what made this feel voice-first when most
                        // questions are typed; showing it the moment the mic
                        // opens keeps what it was good at, which is making it
                        // obvious the app is hearing you.
                        if model.phase == .listening || model.phase == .thinking {
                            GlassGlobe(intensity: model.level, isActive: true)
                                .frame(width: 190, height: 190)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }

                        if model.history.isEmpty && model.answer.isEmpty
                            && model.pendingQuestion.isEmpty {
                            opening
                        } else {
                            transcript
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.phase)

                composer
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory) { historySheet }
        .task { model.appear() }
        .onDisappear { model.disappear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LIFO")
                    .font(LifeOSType.screenTitle)
                    .foregroundStyle(LifoPalette.ink)
                Text("Your life, answered from your own data.")
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifoPalette.quietInk)
            }
            Spacer(minLength: 12)

            if !model.history.isEmpty {
                Button { showHistory = true } label: {
                    Image(systemName: "clock")
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifoPalette.quietInk)
                        .frame(width: 38, height: 38)
                        .glassPane(Circle())
                }
                .accessibilityLabel("History")
            }

            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifoPalette.quietInk)
                    .frame(width: 38, height: 38)
                    .glassPane(Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: - Opening

    private var opening: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 40)

            Text("How can I help you?")
                .font(LifeOSType.display.weight(.semibold))
                .foregroundStyle(LifoPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Suggestions, not a menu: they are the questions this app can
            // actually answer well, phrased the way someone would say them,
            // so the first use is not a blank field and a guess about scope.
            FlowChips(items: Self.suggestions) { prompt in
                model.draft = prompt
                Task { await model.sendTyped() }
            }

            if let error = model.error {
                errorView(error)
                    .padding(.top, 4)
            }
        }
    }

    /// The failure line, and the door out of it when there is one: when the
    /// on-device model is off, the fix is a device setting, so the button
    /// opens Settings rather than describing the journey there.
    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(error)
                .font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifoPalette.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if model.needsAppleIntelligence {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Turn on Apple Intelligence")
                        .font(LifeOSType.label.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Deliberately about this person's own data, because that is what the
    /// coach is scoped to. A suggestion it would decline teaches the wrong
    /// thing about what it is for.
    private static let suggestions = [
        "How did I sleep this week?",
        "Where did my money go?",
        "What should I fix first?",
        "Am I saving enough?",
        "How is my recovery trending?",
    ]

    // MARK: - Transcript

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(model.history) { turn in
                turnView(question: turn.question, answer: turn.answer, sent: turn.sent)
            }

            // The turn in flight. The question is drawn from
            // `pendingQuestion`, which is set the instant it is asked, so it
            // is on screen through the whole wait rather than appearing with
            // the answer it was waiting for.
            if !model.pendingQuestion.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    bubble(model.pendingQuestion, isQuestion: true)

                    if model.answer.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().tint(LifoPalette.ink)
                            Text("Thinking…")
                                .font(LifeOSType.label.weight(.regular))
                                .foregroundStyle(LifoPalette.quietInk)
                        }
                    } else {
                        // The answer as it is written. No cursor and no
                        // per-character animation: the text arrives fast
                        // enough that animating it would slow it down.
                        Text(model.answer)
                            .font(LifeOSType.secondary)
                            .foregroundStyle(LifoPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            if let error = model.error {
                errorView(error)
            }
        }
    }

    private func turnView(question: String, answer: String, sent: SentContext?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // A seeded nudge has no question above it, because LIFO spoke
            // first. An empty bubble there reads as a message the person sent
            // and then deleted.
            if !question.isEmpty {
                bubble(question, isQuestion: true)
            }
            Text(answer)
                .font(LifeOSType.secondary)
                .foregroundStyle(LifoPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let sent {
                sentView(sent)
            }
        }
    }

    /// What this answer was produced from, closed by default and openable.
    ///
    /// Closed, because a line of provenance under every answer would bury the
    /// answers. Openable, because "your own data" is a claim, and the only
    /// honest way to make it is to show the thing itself rather than a
    /// description of it that can drift from what was actually sent.
    private func sentView(_ sent: SentContext) -> some View {
        DisclosureGroup {
            Text(sent.text)
                .font(LifeOSType.caption)
                .foregroundStyle(LifoPalette.quietInk)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 8)
        } label: {
            Label(sent.headline, systemImage: sent.tier == .cloud ? "cloud" : "iphone")
                .font(LifeOSType.caption.weight(.medium))
                .foregroundStyle(LifoPalette.quietInk)
        }
        .tint(LifoPalette.quietInk)
        .padding(.top, 2)
    }

    /// White on the aura, not glass: your own words are the brightest thing
    /// in the transcript, and the answer reads underneath them.
    private func bubble(_ text: String, isQuestion: Bool) -> some View {
        Text(text)
            .font(LifeOSType.label.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(Capsule().fill(.white))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Composer

    /// The field is the primary control and the mic is beside it. The send
    /// button only appears once there is something to send, so the resting
    /// state is a field and one small microphone rather than a row of icons.
    private var composer: some View {
        VStack(spacing: 10) {
            if model.phase == .listening {
                Text(model.liveTranscript.isEmpty ? "Listening…" : model.liveTranscript)
                    .font(LifeOSType.label.weight(.regular))
                    .foregroundStyle(LifoPalette.quietInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 10) {
                // The ask bar is solid white with black type: the one place
                // on this screen where reading and writing must be effortless
                // gets paper, not glass.
                HStack(spacing: 10) {
                    TextField("Ask anything about your life…", text: $model.draft, axis: .vertical)
                        .font(LifeOSType.secondary)
                        .focused($typingFocused)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                        .foregroundStyle(.black)
                        .tint(LifeOSTokens.accent)
                        .onSubmit { Task { await model.sendTyped() } }

                    if !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task { await model.sendTyped() }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(LifeOSType.label.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(LifeOSTokens.accent))
                        }
                        .accessibilityLabel("Send")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white))

                // The mic wears the app's warm accent, filled, in every
                // state: it is the same button whether it is about to listen
                // or about to stop, and colour is how you find it.
                Button {
                    Task { await model.toggleListening() }
                } label: {
                    Image(systemName: model.phase == .listening ? "stop.fill" : "mic.fill")
                        .font(LifeOSType.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(LifeOSTokens.accent))
                        .overlay {
                            if model.phase == .listening {
                                Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            }
                        }
                }
                .accessibilityLabel(model.phase == .listening ? "Stop listening" : "Speak instead")
            }
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.draft.isEmpty)
        }
        .padding(.bottom, 14)
    }

    private func close() {
        model.disappear()
        onDismiss()
    }

    private var historySheet: some View {
        NavigationStack {
            List(model.history) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.question).font(LifeOSType.label.weight(.semibold))
                    Text(turn.answer).font(LifeOSType.label.weight(.regular))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Earlier")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// The glass this screen is made of.
///
/// `.ultraThinMaterial` alone is flat on a dark ground: it frosts, but it has
/// no edge and no light on it, so a chip and a field and a button all read as
/// the same grey smear over the aura. Real glass has a bright top edge where
/// light catches it and a dimmer bottom, and that gradient stroke is what
/// separates one pane from the next without drawing a border around anything.
struct GlassPane: ViewModifier {
    var shape: AnyInsettableShape
    var highlight: Double = 0.34

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                // A wash of the palette inside the frost, so the glass looks
                // lit by the aura behind it rather than laid on top of it.
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), LifoPalette.cyan.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(highlight),
                                 Color.white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

/// Type-erased so `GlassPane` can take a capsule or a rounded rectangle
/// without the modifier becoming generic at every call site.
struct AnyInsettableShape: InsettableShape {
    // `@Sendable` on both: `Shape` is Sendable, so the closures capturing a
    // shape are too, but the compiler cannot see that through the erasure.
    private let makePath: @Sendable (CGRect) -> Path
    private let makeInset: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        makePath = { shape.path(in: $0) }
        makeInset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { makePath(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { makeInset(amount) }
}

extension View {
    func glassPane(_ shape: some InsettableShape, highlight: Double = 0.34) -> some View {
        modifier(GlassPane(shape: AnyInsettableShape(shape), highlight: highlight))
    }
}

/// Chips that wrap onto as many rows as they need.
///
/// `LazyVGrid` cannot do this: its columns are fixed widths, and these are
/// sentences of very different lengths. Laying them out by hand is the only
/// way they pack tightly without a column grid's ragged gaps.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(LifeOSType.label)
                        .foregroundStyle(LifoPalette.ink)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .glassPane(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrapping layout: place each subview on the current row until it
/// does not fit, then start another.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
