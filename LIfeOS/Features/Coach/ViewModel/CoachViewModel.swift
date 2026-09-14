import Foundation
import FoundationModels
import SwiftData
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
    private var voiceTask: Task<Void, Never>?

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

    /// Reads the answer aloud, when asked to.
    ///
    /// Fire and forget, and deliberately not awaited by `send`: the text is
    /// already on screen and a person should be reading it while the audio is
    /// still being fetched, not waiting for it. A failure is silence, which is
    /// the same thing the feature does when it is switched off, so there is
    /// nothing to report.
    private func speak(_ text: String) {
        let defaults = UserDefaults.standard
        guard isVisible, voiceScreenActive, defaults.bool(forKey: AssistantVoice.enabledKey),
              let key = AppConfig.elevenLabsAPIKey
        else { return }

        let voice = AssistantVoice(
            rawValue: defaults.string(forKey: AssistantVoice.voiceKey) ?? ""
        ) ?? .default

        voiceTask?.cancel()
        voiceTask = Task { [voicePlayer] in
            guard let audio = try? await ElevenLabsVoiceClient.speech(
                for: text, voice: voice, apiKey: key
            ) else { return }
            guard !Task.isCancelled else { return }
            voicePlayer.play(audio)
        }
    }

    /// Stops whatever is being said. Asking a new question while the last
    /// answer is still being read out should not produce two voices.
    func stopSpeaking() {
        voiceTask?.cancel()
        voiceTask = nil
        voicePlayer.stop()
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

            let onDevice = Self.coachInstructions(bundle, for: .onDevice)
            let cloud = Self.coachInstructions(bundle, for: .offDevice)

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
                            self.answer = text
                        }
                    }
                )
                guard let owner = accountSessions.load()?.userID,
                      owner == UserDefaults.standard.string(forKey: "accounts.current") else { return }
                let sent = SentContext(
                    text: reply.tier == .cloud ? cloud : onDevice,
                    tier: reply.tier
                )
                try? store.append(conversationID: conversationID, role: .assistant,
                                  text: reply.text)
                answer = reply.text
                history.append(LifoTurn(question: question, answer: reply.text, sent: sent))
                pendingQuestion = ""
                pendingSent = nil
                phase = .answered
                status = "LIFO"
                speak(CoachResponse(reply.text).spokenText)
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
        _ bundle: ContextBundle, for audience: MetricsDigest.Audience
    ) -> String {
        """
        You answer questions about one person's life: their health metrics, \
        money, and life-sector scores.

        \(CoachPresentation.instruction)

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
    }
}
