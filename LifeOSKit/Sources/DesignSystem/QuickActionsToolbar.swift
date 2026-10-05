import SwiftUI

/// The app's actions, injected once at the composition root so any screen can
/// put them in its own navigation bar.
///
/// An environment value rather than a parameter because the screens that need
/// them are not all reachable from one place: Notes and Life own their own
/// `NavigationStack`s several levels below `RootView`, and a toolbar has to be
/// attached inside the stack it belongs to.
public extension EnvironmentValues {
    /// Empty by default, so a screen rendered in a preview without the shell's
    /// injection draws no bar rather than crashing for want of one.
    @Entry var quickActions: [QuickAction] = []
    /// Who is signed in. Nil draws no avatar, for the same reason.
    @Entry var shellProfile: ShellProfile? = nil
}

/// The signed-in person for the bar: their photo, and what the avatar opens.
public struct ShellProfile {
    public let photo: Data?
    public let open: () -> Void

    public init(photo: Data?, open: @escaping () -> Void) {
        self.photo = photo; self.open = open
    }
}

/// The one header every tab carries: the actions, then the avatar outermost.
///
/// `.primaryAction` rather than `.topBarTrailing`: the placement resolves to
/// the trailing edge on iOS and the package still builds for macOS, which has
/// no top bar to name. Items keep declaration order, so the avatar, declared
/// last, sits at the edge.
public struct ShellToolbar: ViewModifier {
    @Environment(\.quickActions) private var actions
    @Environment(\.shellProfile) private var profile
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public func body(content: Content) -> some View {
        paper(content)
            .toolbar {
                if !actions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ActionFan(actions: actions, arrangement: .row)
                    }
                }
                if let profile {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: profile.open) { ProfileAvatar(photo: profile.photo) }
                            .accessibilityLabel("Profile and settings")
                    }
                }
            }
    }

    /// The bar is paper, not system material: a translucent bar over a
    /// masthead reads as a second, blurrier masthead.
    @ViewBuilder private func paper(_ content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(LifeOSTokens.canvas.resolve(scheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        content
        #endif
    }
}

public extension View {
    /// The app's header across the top of this screen. Every tab calls this.
    func shellToolbar() -> some View {
        modifier(ShellToolbar())
    }

    @available(*, deprecated, renamed: "shellToolbar")
    func quickActionsToolbar() -> some View {
        modifier(ShellToolbar())
    }
}
