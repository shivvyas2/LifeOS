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
        // Ink, not the app tint: the caret and selection in the composer are
        // the one place the accent could otherwise reach this screen. After
        // the inset, so the composer inside it inherits it too.
        .tint(ink)
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
                Image(systemName: LifeOSMark.symbol)
                    .font(LifeOSType.sectionTitle)
                    .foregroundStyle(LifeOSTokens.accent)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .text ? "Your personal coach" : "Voice conversation").editorialEyebrow()
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
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
                    if !model.answer.isEmpty {
                        CoachResponseView(text: model.answer, revealed: model.revealedBlocks)
                    } else if model.phase == .thinking {
                        // Only while a reply is actually on its way: after a
                        // failure the error line below says what happened.
                        ChatThinking()
                    }
                }
            }

            if let error = model.error { errorView(error) }
        }
    }

    private func turnView(question: String, answer: String, sent: SentContext?) -> some View {
        ChatTurn(question: question) {
            CoachResponseView(text: answer, animates: false)
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
                if let notice = model.voiceNotice {
                    Text(notice).font(LifeOSType.caption).foregroundStyle(quiet)
                }
                if model.phase == .listening && !model.liveTranscript.isEmpty {
                    Text(model.liveTranscript).font(LifeOSType.body).foregroundStyle(ink)
                        .textSelection(.enabled)
                }
                if !model.pendingQuestion.isEmpty {
                    ChatTurn(question: model.pendingQuestion) {
                        if !model.answer.isEmpty { CoachResponseView(text: model.answer, revealed: model.revealedBlocks) }
                    }
                } else if let turn = model.history.last {
                    ChatTurn(question: turn.question) {
                        CoachResponseView(text: turn.answer, animates: false)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationDetents([.large])
    }
}
