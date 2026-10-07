import SwiftUI
import DesignSystem

/// The walkthrough's overlay. While it runs the screen stays dimmed and inert,
/// with the cut-out and card only once the current step's anchor is on screen.
struct NotesWalkthroughLayer: View {
    let walkthrough: NotesWalkthrough

    var body: some View {
        if let step = walkthrough.currentStep {
            let frame = walkthrough.frames.frames[step.anchor]
            WalkthroughOverlay(step: step, frame: frame, isLast: walkthrough.isLastStep,
                               onNext: { walkthrough.next() }, onSkip: { walkthrough.skip() })
                .ignoresSafeArea()
                .transition(.opacity)
                // An anchor that goes mid-step starts the wait again.
                .onChange(of: frame == nil) { _, lost in
                    if lost { walkthrough.watchForAnchor() }
                }
        }
    }
}
