import SwiftUI
import DesignSystem
import Soundscape

/// How the session went, and for a project task, whether it is done.
struct FocusSummaryView: View {
    let summary: FocusSessionModel.Summary
    var onMarkDone: () -> Void
    var onDone: () -> Void
    @State private var marked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text("SESSION").editorialEyebrow()
            Text(minutes).font(LifeOSType.display)
            if summary.blocks > 0 {
                Text("\(summary.blocks) \(summary.blocks == 1 ? "block" : "blocks") completed").font(LifeOSType.body)
            }
            if let title = summary.taskTitle, summary.taskID != nil {
                Button(marked ? "Marked done" : "Mark \u{201C}\(title)\u{201D} done") { onMarkDone(); marked = true }
                    .buttonStyle(.editorial(.secondary, size: .regular, fullWidth: true))
                    .disabled(marked)
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.editorial(.primary, size: .regular, fullWidth: true))
                .accessibilityIdentifier("focus.summary.done")
        }
        .padding(Space.x3)
        .accessibilityIdentifier("focus.summary")
    }

    private var minutes: String {
        let m = Int(summary.focusedSeconds / 60)
        let label = summary.mood == .sleep ? "listened" : "focused"
        return m >= 60 ? "\(m / 60)h \(m % 60)m \(label)" : "\(m) min \(label)"
    }
}
