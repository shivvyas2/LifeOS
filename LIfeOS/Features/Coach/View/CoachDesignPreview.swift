#if DEBUG
import SwiftUI
import DesignSystem

/// Visual fixtures only. Audio levels are simulated; no microphone or provider calls.
struct CoachDesignPreview: View {
    @State private var model = CoachViewModel()
    @State private var simulatedAudio = ProcessInfo.processInfo.arguments.contains("--voice")

    var body: some View {
        VStack(spacing: 0) {
            previewControls
            LifoCoachScreen(model: model, onDismiss: {})
        }
        .preferredColorScheme(.dark)
        .task {
            model.history = [LifoTurn(question: "Give me a quick look at my week.", answer: Self.sample)]
        }
        .task(id: simulatedAudio) { await animateSample() }
    }

    private var previewControls: some View {
        HStack {
                Text("PREVIEW · SAMPLE REPLY").font(.caption2)
                Spacer()
                Toggle("Sound", isOn: $simulatedAudio).font(.caption).fixedSize()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func animateSample() async {
        model.phase = simulatedAudio ? .listening : .answered
        guard simulatedAudio else { model.level = 0; return }
        var time: Double = 0
        while !Task.isCancelled {
            let syllable = sin(time * 3.6) * 0.6
            let detail = sin(time * 8.0) * 0.2
            model.level = CGFloat(max(0.0, syllable + detail))
            time += 0.08
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private static let sample = """
    Your week, at a glance. Here are the numbers you’ve recorded.

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

#Preview { CoachDesignPreview() }
#endif
