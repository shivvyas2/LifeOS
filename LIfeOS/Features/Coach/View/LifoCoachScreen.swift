import SwiftUI
import UIKit
import DesignSystem
import Insights

/// Two presentations of one conversation. Changing screens never recreates the model.
struct LifoCoachScreen: View {
    @Bindable var model: CoachViewModel
    var onDismiss: () -> Void
    var initialMode: CoachScreenStyle = .text

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @FocusState private var typingFocused: Bool
    @State private var showHistory = false
    @State private var mode: CoachScreenStyle = .text

    private var isEmpty: Bool {
        model.history.isEmpty && model.answer.isEmpty && model.pendingQuestion.isEmpty
    }
    private var activityLevel: CGFloat {
        if model.phase == .listening { return model.level }
        return model.voicePlayer.isSpeaking ? model.voicePlayer.level : 0
    }

    var body: some View {
        ZStack {
            LifoAura(style: mode, intensity: activityLevel,
                     isActive: model.phase == .listening || model.voicePlayer.isSpeaking)
            VStack(spacing: 0) {
                header
                if mode == .text { textScreen } else { voiceScreen }
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if mode == .text { textComposer } else { voiceControls }
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
            .background(mode.night)
        }
        .preferredColorScheme(.dark)
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

    private var header: some View {
        HStack(spacing: 12) {
            if mode == .voice {
                iconButton("chevron.left", label: "Back to text chat") { switchMode(.text) }
            } else {
                Image(systemName: "sparkle")
                    .font(.title3).foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.10), in: Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("LIFO").font(LifeOSType.rowTitle)
                Text(mode == .text ? "Your personal coach" : "Voice conversation")
                    .font(LifeOSType.caption).foregroundStyle(LifoPalette.quietInk)
            }
            Spacer(minLength: 0)
            if !model.history.isEmpty {
                iconButton("clock", label: "Conversation history") { showHistory = true }
            }
            iconButton("xmark", label: "Close coach") { model.disappear(); onDismiss() }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium))
                .foregroundStyle(.white).frame(width: 44, height: 44)
                .background(.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private var textScreen: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if isEmpty {
                            opening.frame(minHeight: max(0, geometry.size.height - 40))
                        } else {
                            transcript
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
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
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("A little clarity.\nA better day.")
                    .font(LifeOSType.display.weight(.medium))
                    .tracking(-1).fixedSize(horizontal: false, vertical: true)
                Text("Make sense of your health, money, and everyday life. One question at a time.")
                    .font(LifeOSType.body).foregroundStyle(LifoPalette.quietInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
            Spacer(minLength: 44)
            VStack(alignment: .leading, spacing: 12) {
                Text("WHERE SHALL WE START?")
                    .font(LifeOSType.caption.weight(.semibold)).tracking(1.5)
                    .foregroundStyle(LifoPalette.quietInk)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { suggestions }
                    VStack(spacing: 10) { suggestions }
                }
            }
            if let error = model.error { errorView(error) }
        }
        .foregroundStyle(.white)
    }

    private var suggestions: some View {
        ForEach(Array(Self.prompts.enumerated()), id: \.offset) { _, item in
            Button {
                model.draft = item.question
                Task { await model.sendTyped() }
            } label: {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: item.symbol).font(.body).foregroundStyle(mode.accent)
                    Text(item.title).font(LifeOSType.label.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.up.right").font(.caption)
                        .foregroundStyle(LifoPalette.quietInk)
                }
                .frame(minWidth: 78, maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .padding(14)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.09)))
            }
            .foregroundStyle(.white).buttonStyle(.plain)
            .accessibilityLabel(item.question)
            .disabled(model.phase == .thinking)
        }
    }
    private static let prompts = [
        (symbol: "moon", title: "My sleep", question: "How did I sleep this week?"),
        (symbol: "chart.xyaxis.line", title: "My spending", question: "Where did my money go?"),
        (symbol: "sun.max", title: "My next step", question: "What should I focus on today?")
    ]

    private var voiceScreen: some View {
        ScrollView {
            VStack(spacing: 20) {
                CoachVoiceOrb(level: activityLevel,
                              isResponding: model.phase == .thinking || model.voicePlayer.isSpeaking,
                              isEnabled: scenePhase == .active)
                    .frame(height: isEmpty ? 280 : 160)
                    .frame(maxWidth: 320)
                    .padding(.top, isEmpty ? 28 : 4)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(voiceTitle).font(LifeOSType.sectionTitle)
                    Text(voiceSubtitle).font(LifeOSType.label)
                        .foregroundStyle(LifoPalette.quietInk)
                        .multilineTextAlignment(.center)
                }
                CoachAudioWaveform(level: activityLevel, active: model.phase == .listening || model.voicePlayer.isSpeaking,
                                   color: mode.accent)
                    .frame(maxWidth: 310).frame(height: 56)
                if model.phase == .listening && !model.liveTranscript.isEmpty {
                    Text(model.liveTranscript).font(LifeOSType.body)
                        .multilineTextAlignment(.center).textSelection(.enabled)
                }
                if !model.pendingQuestion.isEmpty {
                    bubble(model.pendingQuestion)
                    if !model.answer.isEmpty {
                        CoachResponseView(text: model.answer, onAura: true, style: mode)
                    }
                } else if let turn = model.history.last {
                    CoachResponseView(text: turn.answer, onAura: true, style: mode)
                    if let sent = turn.sent { sentView(sent) }
                }
                if let error = model.error { errorView(error) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var voiceTitle: String {
        if model.phase == .listening { return "I'm listening" }
        if model.voicePlayer.isSpeaking { return "Let's talk it through" }
        if model.phase == .thinking { return "Connecting the dots…" }
        return "A moment for you"
    }
    private var voiceSubtitle: String {
        if model.phase == .listening { return "Speak naturally. I'll follow along." }
        if model.voicePlayer.isSpeaking { return "Your answer is here to read, too." }
        if model.phase == .thinking { return "Making sense of your question." }
        return "Tap the microphone whenever you're ready."
    }

    private var textComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message LIFO", text: $model.draft,
                          prompt: Text("Ask about your day…").foregroundStyle(LifoPalette.quietInk), axis: .vertical)
                    .font(LifeOSType.body).foregroundStyle(.white)
                    .focused($typingFocused).lineLimit(1...5).tint(mode.accent)
                    .padding(.vertical, 12)
                    .onSubmit { Task { await model.sendTyped() } }
                if !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { Task { await model.sendTyped() } } label: {
                        Image(systemName: "arrow.up").font(.body.bold())
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(mode.accent, in: Circle())
                    }
                    .disabled(model.phase == .thinking).accessibilityLabel("Send message")
                }
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .background(Color(red: 0.075, green: 0.095, blue: 0.16), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.15)))
            Button { switchMode(.voice) } label: {
                Image(systemName: "waveform").font(.title3.weight(.semibold))
                    .foregroundStyle(.white).frame(width: 56, height: 56)
                    .background(mode.accent, in: Circle())
            }
            .accessibilityLabel("Open voice conversation")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
    }

    private var voiceControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 38) {
                iconButton("keyboard", label: "Switch to text chat") { switchMode(.text) }
                Button {
                    if model.voicePlayer.isSpeaking { model.stopSpeaking() }
                    else { Task { await model.toggleListening() } }
                } label: {
                    Image(systemName: model.phase == .listening || model.voicePlayer.isSpeaking ? "stop.fill" : "mic.fill")
                        .font(.title2.weight(.medium)).foregroundStyle(mode.night)
                        .frame(width: 72, height: 72)
                        .background(mode.accent, in: Circle())
                        .padding(12).background(mode.accent.opacity(0.12), in: Circle())
                        .padding(10).background(mode.accent.opacity(0.06), in: Circle())
                }
                .disabled(model.phase == .thinking)
                .accessibilityLabel(model.voicePlayer.isSpeaking ? "Stop speaking" : model.phase == .listening ? "Finish recording and send" : "Start listening")
                iconButton("xmark", label: "End voice conversation") { switchMode(.text) }
            }
            Text(model.phase == .listening ? "Tap to finish" : model.voicePlayer.isSpeaking ? "Tap to stop" : "Tap to speak")
                .font(LifeOSType.caption).foregroundStyle(LifoPalette.quietInk)
        }
        .padding(.top, 8).padding(.bottom, 16)
    }

    private func switchMode(_ destination: CoachScreenStyle) {
        typingFocused = false
        if destination == .text { model.showKeyboard() }
        model.voiceScreenActive = destination == .voice
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { mode = destination }
    }

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
                        CoachResponseView(text: model.answer, onAura: true, style: mode)
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
            CoachResponseView(text: answer, onAura: true, style: mode)

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
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var historySheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.history) { turn in
                        turnView(question: turn.question, answer: turn.answer, sent: turn.sent)
                    }
                }.padding(24)
            }
            .background(mode.night)
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}

/// A rolling amplitude history from the microphone or spoken reply, silent at rest.
private struct CoachAudioWaveform: View {
    let level: CGFloat
    let active: Bool
    let color: Color
    @State private var samples = Array(repeating: CGFloat.zero, count: 48)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                        colors: [Color.white.opacity(0.10), LifoPalette.gold.opacity(0.05)],
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
