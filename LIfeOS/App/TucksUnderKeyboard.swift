import SwiftUI
import UIKit

/// Takes floating chrome out of the way while the software keyboard is up.
///
/// `.ignoresSafeArea(.keyboard)` on the chrome alone does not do this: the
/// shell around it still respects the keyboard, so the shell ends at the
/// keyboard's top edge and the chrome, pinned to the shell's bottom, sits on
/// top of the keys and takes the strip of screen left for writing. The
/// keyboard's own notifications are the reliable signal, as they are for the
/// iPad rail. A hardware keyboard shows only a short shortcut bar, which is
/// not worth hiding the navigation for, so only a keyboard taller than that
/// counts.
struct TucksUnderKeyboard: ViewModifier {
    @State private var keyboardUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(keyboardUp ? 0 : 1)
            .offset(y: keyboardUp && !reduceMotion ? 24 : 0)
            .allowsHitTesting(!keyboardUp)
            .accessibilityHidden(keyboardUp)
            .animation(.easeOut(duration: 0.2), value: keyboardUp)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                keyboardUp = (frame?.height ?? 0) > 120
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardUp = false
            }
    }
}

extension View {
    func tucksUnderKeyboard() -> some View { modifier(TucksUnderKeyboard()) }
}
