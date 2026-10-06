#if DEBUG
import SwiftUI
import DesignSystem

/// Fixture pages for LIFO, mounted by `--design-preview` with `--page=coach`
/// (a reply with cells, a table and steps), `coach-empty` (the opening) or
/// `coach-voice` (the voice screen, listening, with a simulated level).
/// Audio levels are simulated; no microphone or provider calls.
struct CoachDesignPreview: View {
    let page: String
    @State private var model = CoachViewModel()

    var body: some View {
        LifoCoachScreen(model: model, onDismiss: {}, initialMode: page == "coach-voice" ? .voice : .text)
            .task {
                if page != "coach-empty" {
                    model.history = [LifoTurn(question: "Give me a quick look at my week.", answer: Self.sample)]
                }
                if page == "coach-voice" { await animateListening() }
            }
    }

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
