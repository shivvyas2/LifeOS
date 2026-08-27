import Foundation
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
        return CoachRouter(onDevice: OnDeviceEngine(), remote: remote)
    }()
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

    func send(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        speech.stop()
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
            let result = await router.run(AnswerTask(question: question), bundle)
            switch result {
            case .answered(let output), .degraded(let output):
                answer = output.answer
                history.append(LifoTurn(question: question, answer: output.answer))
                phase = .answered
                status = "LIFO"
            case .refused(let reason):
                fail(reason)
            case .exhausted:
                // The allowance, not the connection. Saying "cannot reach"
                // invites a retry that cannot succeed until tomorrow.
                fail("That is today's thinking budget used up. It resets tomorrow.")
            case .unavailable:
                // Three different causes wear this one case, and blaming Apple
                // Intelligence for all of them was wrong the moment a cloud
                // tier existed: a signed-out user has one fix, and it is not
                // a device setting.
                if isSignedIn {
                    fail("LIFO could not reach the cloud just now. Try again in a moment.")
                } else {
                    fail("LIFO thinks on this device with Apple Intelligence. Turn it on in Settings, or sign in to think in the cloud.")
                    needsAppleIntelligence = true
                }
            case .tooLarge:
                fail("That covered too much at once. Try asking about a shorter stretch.")
            }
        } catch {
            fail("Could not load your metrics.")
        }
    }

    private func fail(_ message: String) {
        error = message
        phase = .idle
        status = message
        isTyping = true
    }
}
