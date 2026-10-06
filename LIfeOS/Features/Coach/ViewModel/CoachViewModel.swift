import Foundation
import FoundationModels
import SwiftData
import SwiftUI
import Insights
import Integrations
import Persistence
import OSLog

private let coachLog = Logger(subsystem: "com.shivvyas.lifeos", category: "coach")

enum LifoPhase: Equatable {
    case idle
    case listening
    case thinking
    case answered
}

struct LifoTurn: Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String
    /// What left the phone for this turn, and where it went. Nil for a seeded
    /// opening line, which is LIFO speaking first and sends nothing.
    let sent: SentContext?

    init(id: UUID = UUID(), question: String, answer: String, sent: SentContext? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.sent = sent
    }
}

/// Exactly what one question was answered with, and by which model.
///
/// The app already decided that the two tiers are owed different renders of
/// somebody's data — `.onDevice` carries the raw Whoop series, `.offDevice`
/// does not — and then never showed anyone either. A coach that reads your
/// sleep and your bank balance and will not say which of them it just sent
/// somewhere is asking for trust it has not earned.
///
/// `text` is the verbatim string, not a description of it. A summary of what
/// was sent is a second thing that can be wrong; the thing itself cannot be.
struct SentContext: Equatable {
    let text: String
    let tier: AssistantTurn.Tier

    /// The one-line version, for the row that is shown before it is opened.
    var headline: String {
        let place = tier == .cloud ? "the cloud" : "this device"
        // Lines rather than characters: "1,847 characters" is a number nobody
        // has a feel for, and the render is one fact per line.
        let facts = text.split(separator: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }.count
        return "\(facts) lines of your data, answered on \(place)"
    }
}

/// Owns the LIFO session: speech in, on-device coach out, typed fallback.
@MainActor @Observable
final class CoachViewModel {
    /// Held rather than made per answer: `AVAudioPlayer` stops the instant it
    /// is deallocated, which is how a spoken reply becomes a tenth of a second
    /// of noise.
    let voicePlayer = VoicePlayer()

    var phase: LifoPhase = .idle
    var liveTranscript = ""
    var answer = ""
    var status = "Tap the mic and talk, or type."
    var error: String?
    var history: [LifoTurn] = []
    /// The question being answered right now, held separately from `history`
    /// so it can go on screen the instant it is asked.
    ///
    /// It used to wait for the answer, because a turn was only appended once
    /// there was something to append it with. That meant the one moment you
    /// most want to see what you said — while it is being thought about — was
    /// the one moment nothing showed it, and a spoken question vanished
    /// entirely between the mic closing and the reply landing.
    var pendingQuestion = ""
    /// What was sent with `pendingQuestion`, available before the answer is.
    var pendingSent: SentContext?
    var isTyping = false
    var voiceScreenActive = false
    var draft = ""
    var level: CGFloat = 0
    /// True when the last failure is the on-device model being unavailable,
    /// so the screen can offer the Apple Intelligence setting rather than
    /// just describing it.
    var needsAppleIntelligence = false

    private var context: ModelContext?
    private var isSending = false
    private var isVisible = false

    /// The turn in flight, when its answer is being held back for the voice.
    ///
    /// The spoken line is asked for first and read the moment it lands, so
    /// the voice starts while the cards are still being written. The cards
    /// then wait for the voice to begin, so that what is said comes first and
    /// what is shown comes up under it, rather than a screen full of tables
    /// arriving in silence a second before anyone speaks. `latestShown` keeps
    /// the text that would have been on screen, and `reveal()` puts it there.
    private var holdingAnswer = false
    private var latestShown = ""
    private var heldTurn: LifoTurn?
    private var revealTimeout: Task<Void, Never>?
    /// Set once per turn so a spoken line is read once, not once per chunk.
    private var spokeThisTurn = false
    /// How many rendered blocks of the answer in flight may be on screen:
    /// nil is all of them. Set from the voice as each passage starts, so a
    /// section arrives with the sentence about it rather than before it.
    var revealedBlocks: Int?
    /// One quiet line for the voice screen: `Premium voice resumes on the 1st`
    /// while the month's allowance is spent, otherwise nil.
    var voiceNotice: String?
    /// The track of the turn in flight, as parsed so far, so a passage that
    /// starts can be mapped to its blocks and the count can grow with the stream.
    private var currentTrack: SpokenTrack?
    /// The last passage the player began, so a stream still arriving can
    /// keep that passage's sections filling in.
    private var lastStartedSegment: Int?
    private var narrationStarted = false
    private var narrationTask: Task<Void, Never>?
    private let voiceBudget = VoiceBudget(defaults: .currentAccount)
    /// The premium synthesiser. A closure so a design preview can hand in a
    /// stub that returns a moment of silence and the staged reveal can be
    /// captured without a key or a network.
    var synthesize: @Sendable (_ text: String, _ voice: AssistantVoice, _ apiKey: String) async throws -> Data = {
        try await ElevenLabsVoiceClient.speech(for: $0, voice: $1, apiKey: $2)
    }
    #if DEBUG
    /// Lets a design preview satisfy `voiceAvailable` without a real key.
    var previewVoiceKey: String?
    #endif
    private var turnID = UUID()
    private let accountSessions = KeychainAuthSessionStore()

    /// Whether a session exists, read at the moment of failure rather than
    /// held: it is only ever consulted to choose which sentence to show, and
    /// a cached copy would tell a user who just signed in to sign in again.
    private var isSignedIn: Bool { accountSessions.load() != nil }
    /// The cloud tier, when the project is configured for it.
    ///
    /// `nil` is a real shipping state, not a stub: with no Supabase URL the
    /// coach still answers on-device and says so when it cannot reach
    /// further. The token is read per call rather than captured, because the
    /// session is refreshed while the app runs and a copy taken at launch
    /// would go stale within the hour.
    private let router: CoachRouter = {
        var remote: (any Engine)?
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            let sessions = KeychainAuthSessionStore()
            remote = RemoteEngine(baseURL: url, anonKey: key, accessToken: {
                sessions.load()?.accessToken
            })
        }
        return CoachRouter(
            onDevice: OnDeviceEngine(),
            remote: remote,
            // Read per request rather than captured, so changing it in Settings
            // takes effect on the next question instead of the next launch.
            preference: { .current }
        )
    }()
    /// This screen's own conversation. Not `ChatStore.latestConversationID()`,
    /// which is global: the coach and the calendar assistant share one store,
    /// and reusing whichever id was written last would let each of them read
    /// the other's turns as its own history.
    private var conversationID = UUID()
    private let defaults = UserDefaults.currentAccount

    /// The cloud tier of the conversation, or nil when the project is not
    /// configured. Built by `ChatTier` so the calendar assistant and this
    /// screen cannot drift apart in how they reach the cloud.
    private let chatRemote: (any ChatEngine)? = ChatTier.remote()

    private let speech = SpeechListener()

    /// Set by RootView; pulls the money and sector context that live in other
    /// view models. A closure rather than references, so the coach does not
    /// hold screens it never renders.
    var bundleExtras: (@MainActor () -> (money: ContextBundle.Money?,
                                         sectors: [ContextBundle.Sector],
                                         firstName: String?))?

    func attach(_ context: ModelContext) {
        self.context = context
        if let saved = defaults.string(forKey: "coach.conversationID"), let id = UUID(uuidString: saved) {
            conversationID = id
        } else {
            defaults.set(conversationID.uuidString, forKey: "coach.conversationID")
        }
        let saved = (try? ChatStore(context: context).recent(conversationID: conversationID)) ?? []
        history = []
        var question = ""
        for message in saved {
            if message.role == .user { question = message.text }
            else if message.role == .assistant {
                history.append(LifoTurn(id: message.id, question: question, answer: message.text))
                question = ""
            }
        }
        speech.onPartial = { [weak self] text in
            self?.liveTranscript = text
        }
        speech.onFinal = { [weak self] text in
            Task { await self?.send(text) }
        }
        speech.onLevel = { [weak self] level in
            guard let self, self.phase == .listening else { return }
            self.level = level
        }
        // The mic closes itself when the sentence ends, and the screen has to
        // say so at that moment. Waiting for the transcript would leave it
        // claiming to listen through the whole upload, which reads as the app
        // having missed what was just said.
        speech.onEndOfSpeech = { [weak self] in
            guard let self, self.phase == .listening else { return }
            self.phase = .thinking
            self.status = "Hearing that back\u{2026}"
            self.level = 0
        }
        speech.onError = { [weak self] message in
            self?.error = message
            self?.phase = .idle
            self?.status = "Type below, or try the mic again."
            self?.isTyping = true
        }
    }

    func appear() {
        isVisible = true
        error = nil
    }

    func showKeyboard() {
        // Keep an in-flight answer (or final transcription) intact across screens.
        if phase == .listening {
            speech.stop()
            phase = .idle
            liveTranscript = ""
            level = 0
        }
        stopSpeaking()
        voiceScreenActive = false
        isTyping = true
        if phase != .thinking { status = "Type to talk to LIFO." }
    }

    func disappear() {
        isVisible = false
        speech.stop()
        stopSpeaking()
        if phase == .listening { phase = .idle }
    }

    func toggleListening() async {
        if phase == .listening {
            status = "Hearing that back…"
            await speech.finish()
            if phase == .listening {
                phase = .idle
                status = "Paused"
            }
            return
        }
        await startListening()
    }

    func startListening() async {
        guard phase != .thinking else { return }
        stopSpeaking()
        error = nil
        liveTranscript = ""
        isTyping = false
        phase = .listening
        status = "Go ahead. I stop when you do."
        await speech.start()
        if !speech.isRunning, phase == .listening {
            phase = .idle
            isTyping = true
            status = "Type to talk to LIFO."
        }
    }

    func sendTyped() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase != .thinking, !isSending else { return }
        draft = ""
        isTyping = false
        await send(text)
    }

    /// Whether a reply asked for right now would be read aloud.
    ///
    /// Read at the start of a turn, not at its end: it decides whether the
    /// model is asked for a spoken line at all, and a typed question on the
    /// text screen should cost no extra tokens for a voice nobody will hear.
    private var voiceAvailable: Bool {
        isVisible && voiceScreenActive
            && UserDefaults.standard.bool(forKey: AssistantVoice.enabledKey)
            && voiceKey != nil
    }

    /// The ElevenLabs key, or a preview's stand-in.
    private var voiceKey: String? {
        #if DEBUG
        if let previewVoiceKey { return previewVoiceKey }
        #endif
        return AppConfig.elevenLabsAPIKey
    }

    /// Reads passages aloud in order and lets each one's sections onto the
    /// screen as it starts.
    ///
    /// Fire and forget, and deliberately not awaited by `send`. Passages are
    /// fetched in order, the next while the current plays, so there is never
    /// a gap longer than one fetch. Every passage is debited against the
    /// month's allowance before it is sent; once the allowance is spent the
    /// device voice takes over for the rest of the month. A fetch that fails
    /// is skipped and its sections reveal with the next start, or at once if
    /// nothing else follows. Whatever happens to the audio, the whole answer
    /// is on screen by the end, because silence is acceptable and a blank
    /// screen is not. The turn id keeps a late exit from an old reply from
    /// touching a new one.
    private func queuePassages(_ passages: [(index: Int, text: String)], turn: UUID) {
        guard voiceAvailable, let key = voiceKey, !passages.isEmpty else {
            completeNarration(turn)
            return
        }
        let voice = AssistantVoice(rawValue: UserDefaults.standard.string(forKey: AssistantVoice.voiceKey) ?? "") ?? .default
        let player = voicePlayer
        player.onSegmentStart = { [weak self] index in
            guard let self, turn == self.turnID else { return }
            self.reveal(turn)
            self.lastStartedSegment = index
            if self.revealedBlocks != nil {
                self.revealedBlocks = self.currentTrack?.revealedBlocks(throughSegment: index)
            }
        }
        player.onFinish = { [weak self] in
            self?.completeNarration(turn)
        }
        let synthesize = self.synthesize
        let budget = voiceBudget
        let previous = narrationTask
        narrationTask = Task { [weak self] in
            await previous?.value
            for passage in passages {
                guard !Task.isCancelled, let self, turn == self.turnID else { return }
                let audio: Data?
                if budget.remaining() >= passage.text.count {
                    budget.debit(passage.text.count)
                    audio = try? await synthesize(passage.text, voice, key)
                } else {
                    self.voiceNotice = "Premium voice resumes on the 1st"
                    audio = try? await DeviceVoiceClient.speech(for: passage.text)
                }
                guard !Task.isCancelled, turn == self.turnID else { return }
                guard let audio else { continue }
                let segment = VoiceSegment(index: passage.index, audio: audio)
                if self.narrationStarted { player.append([segment]) } else { player.play([segment]); self.narrationStarted = true }
            }
            // Nothing played at all (every fetch failed): show everything.
            if let self, turn == self.turnID, !self.narrationStarted {
                self.completeNarration(turn)
            }
        }
    }

    /// The narration is over, one way or another: the whole answer is on
    /// screen and the turn, if its reply has finished, joins the transcript.
    private func completeNarration(_ turn: UUID) {
        guard turn == turnID else { return }
        reveal(turn)
        revealedBlocks = nil
        if let heldTurn {
            finish(heldTurn)
            self.heldTurn = nil
        }
    }

    /// Puts the held answer on screen. Idempotent, and a no-op for any turn
    /// but the current one. The turn itself joins the transcript only when
    /// the narration ends (`completeNarration`), because the voice now
    /// outlives the reply and a turn in history reveals all at once.
    private func reveal(_ turn: UUID) {
        guard turn == turnID, holdingAnswer else { return }
        holdingAnswer = false
        revealTimeout?.cancel()
        revealTimeout = nil
        withAnimation(.easeOut(duration: 0.35)) {
            answer = heldTurn?.answer ?? latestShown
        }
    }

    /// The turn is over and on screen: the transcript takes it, the pending
    /// question comes down.
    private func finish(_ turn: LifoTurn) {
        answer = turn.answer
        revealedBlocks = nil
        history.append(turn)
        pendingQuestion = ""
        pendingSent = nil
    }

    /// A chunk of the answer as written so far.
    ///
    /// The opening is read the moment its line lands, while the sections are
    /// still arriving; the later passages are queued when the reply is whole,
    /// in `send`, since a passage is only a passage once its newline has.
    /// While the stream grows, the passage already playing keeps letting its
    /// own sections in.
    private func received(_ text: String) {
        let track = SpokenTrack(parsing: text)
        latestShown = track.shownText
        if holdingAnswer {
            currentTrack = track
            if !spokeThisTurn, let opening = track.opening {
                spokeThisTurn = true
                queuePassages([(index: 0, text: opening)], turn: turnID)
            }
        } else {
            answer = track.shownText
        }
        if let started = lastStartedSegment, revealedBlocks != nil {
            currentTrack = track
            revealedBlocks = track.revealedBlocks(throughSegment: started)
        }
    }

    /// What to say when the model was asked for a track and wrote no passage
    /// at all: the first plain sentence or two of the answer, once, never a
    /// table read aloud.
    private static func fallbackTrack(for shown: String) -> SpokenTrack? {
        for block in CoachResponse(shown).blocks {
            if case .paragraph(let text) = block {
                return SpokenTrack(parsing: "\(SpokenTrack.prefix) \(ResponseStyle.clean(text))\n\n\(shown)", final: true)
            }
        }
        return nil
    }

    /// Stops whatever is being said. Asking a new question while the last
    /// answer is still being read out should not produce two voices.
    func stopSpeaking() {
        narrationTask?.cancel()
        narrationTask = nil
        voicePlayer.stop()
        completeNarration(turnID)
    }

    /// Opens the conversation with something LIFO said first.
    ///
    /// This is the point of the whole proactive design. A notification that
    /// only shows a sentence is a reminder, and the app does not need another
    /// reminder; seeded as the first assistant turn it becomes an opening line
    /// that can be answered, and it is only answerable because the thread
    /// below carries it into the next prompt.
    ///
    /// Written into the store, not just into `history`: the store is what
    /// `send` renders into `messages[]`, so a nudge that skipped it would be
    /// on screen and invisible to the model answering the reply to it.
    func seed(_ text: String) {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        // Already the opening line. A second tap on the same notification
        // should reopen the conversation, not repeat it.
        guard history.first?.answer != sentence else { return }

        if let context {
            try? ChatStore(context: context)
                .append(conversationID: conversationID, role: .assistant, text: sentence)
        }
        // An empty question, because there was none: LIFO spoke first. The
        // transcript draws no bubble above an answer with nothing to quote.
        history.append(LifoTurn(question: "", answer: sentence))
        answer = sentence
        phase = .answered
        status = "LIFO"
        error = nil
    }

    func send(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        speech.stop()
        stopSpeaking()
        liveTranscript = question
        // Pinned before anything else happens, including the store reads
        // below. Whatever the rest of this method does or fails to do, the
        // question is on screen from the moment it was asked.
        pendingQuestion = question
        pendingSent = nil
        answer = ""
        phase = .thinking
        status = "Thinking…"
        level = 0
        needsAppleIntelligence = false
        // A new turn id after `stopSpeaking()`, so the old voice task's exit
        // reveals nothing of this turn. Whether the answer is held for the
        // voice is decided here, once, and it is the same decision as whether
        // the model is asked for a spoken line at all.
        turnID = UUID()
        spokeThisTurn = false
        holdingAnswer = voiceAvailable
        revealedBlocks = holdingAnswer ? 0 : nil
        currentTrack = nil
        lastStartedSegment = nil
        narrationStarted = false
        latestShown = ""
        heldTurn = nil
        revealTimeout?.cancel()
        revealTimeout = nil
        let spokenLine = holdingAnswer

        guard let context else {
            fail("LIFO could not read your metrics.")
            return
        }

        do {
            let end = Calendar.current.startOfDay(for: .now)
            let start = Calendar.current.date(byAdding: .day, value: -13, to: end) ?? end
            let metricsStore = MetricsStore(context: context)
            let rows = try metricsStore.metrics(from: start, to: end)
            let digest = MetricsDigest.from(
                metrics: rows,
                sleeps: try metricsStore.sleepRecords(from: start, to: end),
                workouts: try metricsStore.workouts(from: start, to: end)
            )
            let extras = bundleExtras?()
            let bundle = ContextBundle(
                digest: digest,
                money: extras?.money,
                sectors: extras?.sectors ?? [],
                firstName: extras?.firstName
            )
            let store = ChatStore(context: context)
            try? store.append(conversationID: conversationID, role: .user, text: question)

            let thread = ((try? store.recent(conversationID: conversationID)) ?? [])
                .map { ChatTurnMessage(role: $0.role == .user ? .user : .assistant,
                                       text: $0.text) }

            let onDevice = Self.coachInstructions(bundle, for: .onDevice, spokenLine: spokenLine)
            let cloud = Self.coachInstructions(bundle, for: .offDevice, spokenLine: spokenLine)

            do {
                let reply = try await AssistantTurn.run(
                    // One render per tier, not one render for both. The two
                    // audiences carry different fields on purpose: `.onDevice`
                    // includes HRV, SpO2, skin temperature and respiratory
                    // rate, which are the raw Whoop series and stay on the
                    // phone, and `.offDevice` leaves those out and carries the
                    // money detail instead. Sending one render to both tiers
                    // means picking which tier to be wrong for.
                    instructions: ChatInstructions(onDevice: onDevice, cloud: cloud),
                    thread: thread,
                    tools: [],
                    broker: ConfirmationBroker(),
                    remote: chatRemote,
                    // The answer as it is written. Assigned, never appended:
                    // the engine hands over the whole of it each time, so a
                    // frame that arrives out of order cannot duplicate a
                    // clause or leave one behind.
                    onPartial: { [weak self] text in
                        Task { @MainActor in
                            guard let self, self.phase == .thinking else { return }
                            self.received(text)
                        }
                    }
                )
                guard let owner = accountSessions.load()?.userID,
                      owner == UserDefaults.standard.string(forKey: "accounts.current") else { return }
                let sent = SentContext(
                    text: reply.tier == .cloud ? cloud : onDevice,
                    tier: reply.tier
                )
                // The passages are for the voice and nobody else: not
                // rendered, not kept in the transcript, and not written to the
                // store the next prompt is built from. A reply that was only
                // an opening is shown as itself rather than as nothing.
                let final = SpokenTrack(parsing: reply.text, final: true).capped(to: 700)
                let shown = final.shownText.isEmpty ? (final.opening ?? reply.text) : final.shownText
                try? store.append(conversationID: conversationID, role: .assistant, text: shown)
                let turn = LifoTurn(question: question, answer: shown, sent: sent)
                phase = .answered
                status = "LIFO"
                if holdingAnswer || spokeThisTurn {
                    heldTurn = turn
                    latestShown = shown
                    currentTrack = final
                    if !holdingAnswer { answer = shown }
                    let passages = final.segments.enumerated().compactMap { index, segment in
                        segment.spoken.map { (index: index, text: $0) }
                    }
                    if spokeThisTurn {
                        // The opening is already playing; queue the rest.
                        queuePassages(passages.filter { $0.index > 0 }, turn: turnID)
                    } else if !passages.isEmpty {
                        spokeThisTurn = true
                        queuePassages(passages, turn: turnID)
                    } else if let fallback = Self.fallbackTrack(for: shown), let opening = fallback.opening {
                        spokeThisTurn = true
                        currentTrack = fallback
                        queuePassages([(index: 0, text: opening)], turn: turnID)
                    } else {
                        completeNarration(turnID)
                    }
                    // Whatever the voice does, the answer is on screen within
                    // two seconds of being finished. A slow synthesis is a
                    // reason to read first, not a reason to see nothing.
                    let id = turnID
                    revealTimeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled, let self, id == self.turnID else { return }
                        self.reveal(id)
                        if self.lastStartedSegment == nil { self.completeNarration(id) }
                    }
                } else {
                    finish(turn)
                }
            } catch RemoteEngineError.refused(let reason) {
                fail(reason)
            } catch RemoteEngineError.exhausted {
                fail("That is today's thinking budget used up. It resets tomorrow.")
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                // The on-device model's context window, not the network: the
                // cloud message above and the Apple Intelligence prompt below
                // both misdiagnose this as a connectivity or settings problem.
                fail("That covered too much at once. Try asking about a shorter stretch.")
            } catch RemoteEngineError.notSignedIn {
                // Its own case, not the network one below. The message used to
                // be "could not reach the cloud", which sent someone whose
                // session had simply lapsed to check their wifi.
                fail("Your session has expired. Sign in again to think in the cloud.")
            } catch {
                // The one place the real reason is visible. Every failure past
                // this point renders as the same sentence, so without this
                // line a lapsed token, a 500 from the function and a plane
                // journey are indistinguishable from the outside — which is
                // how "LIFO could not reach the cloud" becomes unanswerable.
                coachLog.error("cloud turn failed: \(String(describing: error), privacy: .public)")
                if isSignedIn {
                    fail("LIFO could not reach the cloud just now. Try again in a moment.")
                } else {
                    fail("LIFO thinks on this device with Apple Intelligence. Turn it on in Settings, or sign in to think in the cloud.")
                    needsAppleIntelligence = true
                }
            }
        } catch {
            fail("Could not load your metrics.")
        }
    }

    /// The data bundle as one tier is allowed to see it.
    private static func coachInstructions(
        _ bundle: ContextBundle, for audience: MetricsDigest.Audience, spokenLine: Bool
    ) -> String {
        """
        You answer questions about one person's life: their health metrics, \
        money, and life-sector scores.

        \(CoachPresentation.instruction)
        \(spokenLine ? CoachPresentation.spokenTrackInstruction : "")

        Here is what their data shows:

        \(bundle.promptLines(for: audience))
        """
    }

    private func fail(_ message: String) {
        error = message
        phase = .idle
        status = message
        isTyping = true
        // A streamed answer that broke off half way is not an answer. Leaving
        // the fragment on screen under a failure line reads as though LIFO
        // said something and then contradicted itself.
        answer = ""
        pendingSent = nil
        holdingAnswer = false
        heldTurn = nil
        revealedBlocks = nil
        revealTimeout?.cancel()
        revealTimeout = nil
    }

    #if DEBUG
    /// Runs the post-reply path on a canned reply, for the design preview:
    /// holds the answer, narrates through `synthesize`, reveals per passage.
    func previewNarrate(_ reply: String) {
        stopSpeaking()
        turnID = UUID()
        spokeThisTurn = true
        holdingAnswer = true
        revealedBlocks = 0
        lastStartedSegment = nil
        narrationStarted = false
        pendingQuestion = "Give me a quick look at my week."
        answer = ""
        phase = .answered
        let final = SpokenTrack(parsing: reply, final: true).capped(to: 700)
        let shown = final.shownText
        heldTurn = LifoTurn(question: pendingQuestion, answer: shown)
        latestShown = shown
        currentTrack = final
        let passages = final.segments.enumerated().compactMap { index, segment in
            segment.spoken.map { (index: index, text: $0) }
        }
        queuePassages(passages, turn: turnID)
    }
    #endif
}
