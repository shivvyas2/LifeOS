import Foundation
import FoundationModels
import SwiftData
import Insights
import Integrations
import Persistence

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

    init(id: UUID = UUID(), question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
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
    var status = "Tap the mic, or type."
    var error: String?
    var history: [LifoTurn] = []
    var isTyping = false
    var draft = ""
    var level: CGFloat = 0
    /// True when the last failure is the on-device model being unavailable,
    /// so the screen can offer the Apple Intelligence setting rather than
    /// just describing it.
    var needsAppleIntelligence = false

    private var context: ModelContext?

    /// Whether a session exists, read at the moment of failure rather than
    /// held: it is only ever consulted to choose which sentence to show, and
    /// a cached copy would tell a user who just signed in to sign in again.
    private var isSignedIn: Bool { KeychainAuthSessionStore().load() != nil }
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
            remote = RemoteEngine(baseURL: url, anonKey: key, accessToken: {
                KeychainAuthSessionStore().load()?.accessToken
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
    private let conversationID = UUID()

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
        speech.onPartial = { [weak self] text in
            self?.liveTranscript = text
        }
        speech.onFinal = { [weak self] text in
            Task { await self?.send(text) }
        }
        speech.onLevel = { [weak self] level in
            self?.level = level
        }
        speech.onError = { [weak self] message in
            self?.error = message
            self?.phase = .idle
            self?.status = "Type below, or try the mic again."
            self?.isTyping = true
        }
    }

    func appear() {
        error = nil
    }

    func showKeyboard() {
        speech.stop()
        phase = .idle
        isTyping = true
        status = "Type to talk to LIFO."
    }

    func disappear() {
        speech.stop()
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
        error = nil
        liveTranscript = ""
        isTyping = false
        phase = .listening
        status = "Go ahead, I'm listening…"
        await speech.start()
        if !speech.isRunning, phase == .listening {
            phase = .idle
            isTyping = true
            status = "Type to talk to LIFO."
        }
    }

    func sendTyped() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
        guard defaults.bool(forKey: AssistantVoice.enabledKey),
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
        guard !question.isEmpty else { return }
        speech.stop()
        stopSpeaking()
        liveTranscript = question
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

            do {
                let reply = try await AssistantTurn.run(
                    // One render per tier, not one render for both. The two
                    // audiences carry different fields on purpose: `.onDevice`
                    // includes HRV, SpO2, skin temperature and respiratory
                    // rate, which are the raw Whoop series and stay on the
                    // phone, and `.offDevice` leaves those out and carries the
                    // money detail instead. Sending one render to both tiers
                    // means picking which tier to be wrong for.
                    instructions: ChatInstructions(
                        onDevice: Self.coachInstructions(bundle, for: .onDevice),
                        cloud: Self.coachInstructions(bundle, for: .offDevice)
                    ),
                    thread: thread,
                    tools: [],
                    broker: ConfirmationBroker(),
                    remote: chatRemote
                )
                try? store.append(conversationID: conversationID, role: .assistant,
                                  text: reply.text)
                answer = reply.text
                history.append(LifoTurn(question: question, answer: reply.text))
                phase = .answered
                status = "LIFO"
                speak(reply.text)
            } catch RemoteEngineError.refused(let reason) {
                fail(reason)
            } catch RemoteEngineError.exhausted {
                fail("That is today's thinking budget used up. It resets tomorrow.")
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                // The on-device model's context window, not the network: the
                // cloud message above and the Apple Intelligence prompt below
                // both misdiagnose this as a connectivity or settings problem.
                fail("That covered too much at once. Try asking about a shorter stretch.")
            } catch {
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

        Here is what their data shows:

        \(bundle.promptLines(for: audience))
        """
    }

    private func fail(_ message: String) {
        error = message
        phase = .idle
        status = message
        isTyping = true
    }
}
