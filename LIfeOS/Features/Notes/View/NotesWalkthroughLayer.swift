import SwiftUI
import DesignSystem

/// The walkthrough's overlay, drawn only once the current step's anchor is on
/// screen: while a page is opening there is no cut-out to draw yet.
struct NotesWalkthroughLayer: View {
    let walkthrough: NotesWalkthrough

    var body: some View {
        if let step = walkthrough.currentStep, let frame = walkthrough.frames.frames[step.anchor] {
            WalkthroughOverlay(step: step, frame: frame, isLast: walkthrough.isLastStep,
                               onNext: { walkthrough.next() }, onSkip: { walkthrough.skip() })
                .ignoresSafeArea()
                .transition(.opacity)
        }
    }
}
