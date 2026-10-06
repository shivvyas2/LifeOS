#if DEBUG
import SwiftUI
import DesignSystem
import Insights
import Persistence

/// Fixture pages for LIFO, mounted by `--design-preview` with `--page=coach`
/// (a reply with cells, a table and steps), `coach-empty` (the opening) or
/// `coach-voice` (the voice screen, listening, with a simulated level).
/// `coach-voice --track=3` narrates a canned three-passage reply through a
/// stub synthesiser (`--fail=N` refuses passage N, `--budget-spent` shows the
/// device-voice line). Audio levels are simulated; no microphone or provider calls.
struct CoachDesignPreview: View {
    let page: String
    @State private var model = CoachViewModel()

    var body: some View {
        LifoCoachScreen(model: model, onDismiss: {}, initialMode: page == "coach-voice" ? .voice : .text)
            .task {
                let args = ProcessInfo.processInfo.arguments
                let narrating = args.contains { $0.hasPrefix("--track=") }
                if page != "coach-empty", !narrating {
                    model.history = [LifoTurn(question: "Give me a quick look at my week.", answer: Self.sample)]
                }
                if page == "coach-voice" {
                    if narrating {
                        // A stub synthesiser: a moment of silence per passage,
                        // refusing passage N when `--fail=N` is passed, so the
                        // staged reveal can be captured frame by frame.
                        let failing = args.first { $0.hasPrefix("--fail=") }.flatMap { Int($0.dropFirst(7)) }
                        let calls = Counter()
                        model.previewVoiceKey = "preview"
                        UserDefaults.standard.set(true, forKey: AssistantVoice.enabledKey)
                        model.synthesize = { _, _, _ in
                            let call = calls.next()
                            if let failing, call == failing { throw VoiceSynthesisError.remoteFailed }
                            return Self.silence(seconds: 0.8)
                        }
                        if args.contains("--budget-spent") {
                            VoiceBudget(defaults: .currentAccount).debit(VoiceBudget.monthlyAllowance)
                        }
                        try? await Task.sleep(for: .milliseconds(600))
                        model.previewNarrate(Self.narrated)
                    } else {
                        await animateListening()
                    }
                }
            }
    }

    /// Counts stub calls from inside a Sendable closure.
    nonisolated private final class Counter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }

    /// A WAV of silence, so the player runs for a known time and the reveal
    /// can be watched frame by frame.
    nonisolated static func silence(seconds: Double) -> Data {
        let sampleRate: UInt32 = 16_000
        let frames = Int(Double(sampleRate) * seconds)
        let pcm = Data(count: frames * 2)
        var header = Data()
        func put<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; header.append(Data(bytes: &v, count: MemoryLayout<T>.size)) }
        header.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1)); put(sampleRate); put(sampleRate * 2); put(UInt16(2)); put(UInt16(16))
        header.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return header + pcm
    }

    /// The sample reply with three passages, the shape the spoken track asks for.
    static let narrated = """
    SAY: Honestly, you slept well this week. Keep that wake time.

    Your week, at a glance. Here are the numbers you've recorded.

    | Metric | This week |
    | --- | --- |
    | Average sleep | 7h 24m |
    | Recovery | 72% |

    SAY: Both are up a notch on last week, and recovery is the one to watch.

    ## Compared with last week
    | Measure | Last week | This week |
    | --- | --- | --- |
    | Steps / day | 7,420 | 8,610 |
    | Sleep | 7h 02m | 7h 24m |

    SAY: One small thing tonight, and that is plenty.

    ## Next up
    - Review your latest sleep entries.
    - Pick one priority for tomorrow.
    """

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
