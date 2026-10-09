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
    /// The way back to the tab a screen was opened from, for the screens that
    /// live behind a tab rather than on the bar. Nil draws nothing.
    @Entry var shellBack: ShellBack? = nil
}

/// A leading "‹ Life" in the bar: where the screen was opened from.
public struct ShellBack {
    public let label: String
    public let action: () -> Void

    public init(label: String, action: @escaping () -> Void) {
        self.label = label; self.action = action
    }
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
    @Environment(\.shellBack) private var back
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public func body(content: Content) -> some View {
        paper(content)
            .toolbar {
                #if os(iOS)
                if let back {
                    ToolbarItem(placement: .topBarLeading) {
                        // Spelled out rather than a Label: the bar draws a
                        // Label as its icon alone, and a bare chevron does not
                        // say where it goes.
                        Button(action: back.action) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").font(LifeOSType.label.weight(.semibold))
                                Text(back.label).font(LifeOSType.label.weight(.medium))
                            }
                            .fixedSize()
                        }
                        .tint(LifeOSTokens.primaryText.resolve(scheme))
                        .accessibilityLabel("Back to \(back.label)")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                #endif
                // No shared glass capsule behind the items: the bar is paper
                // and the items sit on it bare, the way the row is designed.
                if !actions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ActionFan(actions: actions, arrangement: .row)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if let profile {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: profile.open) { ProfileAvatar(photo: profile.photo) }
                            .accessibilityLabel("Profile and settings")
                    }
                    .sharedBackgroundVisibility(.hidden)
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
