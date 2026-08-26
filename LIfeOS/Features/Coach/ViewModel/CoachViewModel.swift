import Foundation
import SwiftData
import Insights
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

    private var context: ModelContext?
    private let router = CoachRouter(onDevice: OnDeviceEngine(), remote: nil)
    private let speech = SpeechListener()

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
            let result = await router.run(AnswerTask(question: question), digest)
            switch result {
            case .answered(let output), .degraded(let output):
                answer = output.answer
                history.append(LifoTurn(question: question, answer: output.answer))
                phase = .answered
                status = "LIFO"
            case .refused(let reason):
                fail(reason)
            case .exhausted:
                fail("LIFO cannot reach further right now.")
            case .unavailable:
                fail("LIFO needs Apple Intelligence on this device. You can still type — try again after it is on.")
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
