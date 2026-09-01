import SwiftUI

/// The app's actions, injected once at the composition root so any screen can
/// put them in its own navigation bar.
///
/// An environment value rather than a parameter because the screens that need
/// them are not all reachable from one place: Notes and Life own their own
/// `NavigationStack`s several levels below `RootView`, and a toolbar has to be
/// attached inside the stack it belongs to. Threading a `[QuickAction]` down
/// through both would put the same three buttons in four call sites, which is
/// how the set drifts apart.
public extension EnvironmentValues {
    /// Empty by default, so a screen rendered in a preview without the shell's
    /// injection draws no bar rather than crashing for want of one.
    @Entry var quickActions: [QuickAction] = []
}

/// Puts the injected actions in the navigation bar, laid flat.
///
/// `.primaryAction` rather than `.topBarTrailing`: the placement resolves to
/// the trailing edge on iOS and the package still builds for macOS, which has
/// no top bar to name.
///
/// Applied nearest the content on a screen that has other bar items, since
/// items appear in the order their modifiers are applied and these should sit
/// inboard of anything the screen adds for itself.
public struct QuickActionsToolbar: ViewModifier {
    @Environment(\.quickActions) private var actions

    public init() {}

    public func body(content: Content) -> some View {
        content.toolbar {
            if !actions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ActionFan(actions: actions, arrangement: .row)
                }
            }
        }
    }
}

public extension View {
    /// The app's actions across the top of this screen.
    ///
    /// Every tab calls this. The actions used to live in a fan pinned to the
    /// bottom-trailing corner on every screen except home, which meant the one
    /// control people reach for most sat in a different place depending on
    /// which tab they were on, and on four of the five it was collapsed behind
    /// a trigger. One place, always open, is worth the bar it costs.
    func quickActionsToolbar() -> some View {
        modifier(QuickActionsToolbar())
    }
}
