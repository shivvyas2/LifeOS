import SwiftUI
import UIKit
import DesignSystem
import Insights

/// A voice-reactive coach with readable response cards and a persistent text composer.
struct LifoCoachScreen: View {
    @Bindable var model: CoachViewModel
    var onDismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @FocusState private var typingFocused: Bool
    @State private var showHistory = false

    var body: some View {
        ZStack {
            LifoAura(intensity: activityLevel,
                     isActive: model.phase == .listening || model.voicePlayer.isSpeaking)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        voicePresence

                        if model.history.isEmpty && model.answer.isEmpty
                            && model.pendingQuestion.isEmpty {
                            opening
                        } else {
                            transcript
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: model.phase)

                composer
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory) { historySheet }
        .task { model.appear() }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appear() } else { model.disappear() }
        }
    }

    private var activityLevel: CGFloat {
        if model.phase == .listening { return model.level }
        return model.voicePlayer.isSpeaking ? model.voicePlayer.level : 0
    }

    private var voicePresence: some View {
        VStack(spacing: 8) {
            CoachVoiceOrb(level: activityLevel,
                          isResponding: model.phase == .thinking || model.voicePlayer.isSpeaking,
                          isEnabled: scenePhase == .active)
                .frame(width: 170, height: 154)
            HStack(spacing: 8) {
                if model.phase == .listening {
                    Circle().fill(LifeOSTokens.accent).frame(width: 6, height: 6)
                    Text("Listening to you")
                } else if model.voicePlayer.isSpeaking {
                    Text("Speaking")
                    Button("Stop") { model.stopSpeaking() }
                        .foregroundStyle(LifeOSTokens.accent).frame(minHeight: 44)
                } else if model.phase == .thinking {
                    Text("Putting it together…")
                } else {
                    Text("Type below, or tap the mic")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(LifoPalette.quietInk)
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity)
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
                        .frame(width: 44, height: 44)
                        .glassPane(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("History")
            }

            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifoPalette.quietInk)
                    .frame(width: 44, height: 44)
                    .glassPane(RoundedRectangle(cornerRadius: 12))
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
            Spacer(minLength: 4)

            Text("How can I help you?")
                .font(LifeOSType.display.weight(.semibold))
                .foregroundStyle(LifoPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Suggestions, not a menu: they are the questions this app can
            // actually answer well, phrased the way someone would say them,
            // so the first use is not a blank field and a guess about scope.
            VStack(spacing: 10) {
                ForEach(Self.suggestions.prefix(3), id: \.self) { prompt in
                    Button {
                        model.draft = prompt
                        Task { await model.sendTyped() }
                    } label: {
                        HStack(spacing: 14) {
                            Text(prompt).font(.subheadline)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left").foregroundStyle(LifeOSTokens.accent)
                        }
                        .foregroundStyle(LifoPalette.ink)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.06, green: 0.12, blue: 0.29).opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
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
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
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
                    bubble(model.pendingQuestion)

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
                        CoachResponseView(text: model.answer, onAura: true)
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
                bubble(question)
            }
            CoachResponseView(text: answer, onAura: true)

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
    private func bubble(_ text: String) -> some View {
        Text(text)
            .font(LifeOSType.label.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
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
                    TextField("Ask LIFO", text: $model.draft,
                              prompt: Text("Ask about your life…").foregroundStyle(Color.black.opacity(0.55)),
                              axis: .vertical)
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
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 14).fill(LifeOSTokens.accent))
                        }
                        .disabled(model.phase == .thinking)
                        .accessibilityLabel("Send")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))

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
                        .background(RoundedRectangle(cornerRadius: 14).fill(LifeOSTokens.accent))
                        .overlay {
                            if model.phase == .listening {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            }
                        }
                }
                .disabled(model.phase == .thinking)
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
                    CoachResponseView(text: turn.answer)
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
