import SwiftUI

/// One of the app's free-floating actions: the calendar assistant, LIFO, and
/// quick log. Not navigation, which is what keeps these out of `PillNavBar`.
public struct QuickAction: Identifiable {
    public let id: String
    public let systemImage: String
    public let label: String
    /// The one drawn as a filled circle rather than glass. Exactly one action
    /// in a set should carry it, the same way one tab in the pill bar is
    /// selected: it is what the eye lands on first.
    public let isProminent: Bool
    /// A word or two drawn beside the prominent action's glyph in the row.
    /// The glyph alone was a guess: a plus could mean add a note, a habit or
    /// a transaction, and only the label says it starts an activity.
    public let shortLabel: String?
    public let action: () -> Void

    public init(
        id: String,
        systemImage: String,
        label: String,
        isProminent: Bool = false,
        shortLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.systemImage = systemImage
        self.label = label
        self.isProminent = isProminent
        self.shortLabel = shortLabel
        self.action = action
    }
}

/// Which of the two shapes the same set of actions takes.
public enum ActionFanArrangement {
    /// Laid out flat, all of them visible. The home screen, where there is
    /// room across the top and where these actions are the point of the screen.
    case row
    /// Collapsed behind one trigger that arcs them out on tap. Every other
    /// screen, where three permanent circles sit on top of somebody's content.
    case fan
}

/// The app's actions in two arrangements, one component rather than two.
///
/// The reasoning is `PillNavBar`'s: a row and a fan drawn from separate views
/// would define the same circle in two places, and that is how the two drift
/// apart. Here the button is written once and only its position changes.
///
/// The fan is anchored bottom-trailing and opens up and to the left, which is
/// where the space is on a phone: the pill bar owns the bottom centre and the
/// content owns everything above. Items arc between straight up and just shy
/// of straight left, so the furthest one still clears the bar.
public struct ActionFan: View {
    private let actions: [QuickAction]
    private let arrangement: ActionFanArrangement
    @Binding private var isOpen: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The arc the items travel along, in degrees counterclockwise from the
    /// trailing edge. Stops short of 180 so the last item sits above the pill
    /// bar rather than beside it.
    private let arcStart: Double = 90
    private let arcEnd: Double = 170
    /// Set by the arc, not by taste. Adjacent items are `2r sin(dTheta/2)`
    /// apart, so with three items across 80 degrees a radius under about 76
    /// puts two 52pt circles through each other. 106 leaves roughly 20pt of
    /// air between them, which is the difference between a fan and a pile.
    private let radius: CGFloat = 106
    private let diameter: CGFloat = 52
    private let prominentDiameter: CGFloat = 56
    /// Fits a 44pt navigation bar with room either side.
    private let rowDiameter: CGFloat = 34

    public init(
        actions: [QuickAction],
        arrangement: ActionFanArrangement,
        isOpen: Binding<Bool> = .constant(true)
    ) {
        self.actions = actions
        self.arrangement = arrangement
        self._isOpen = isOpen
    }

    public var body: some View {
        switch arrangement {
        case .row: row
        case .fan: fan
        }
    }

    // MARK: - Row

    /// Sized for the navigation bar it sits in, not for the corner the fan
    /// holds. A 52pt glass circle does not fit a 44pt bar, and three of them
    /// across the top of a screen is a toolbar pretending to be a dock.
    private var row: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                button(action)
            }
        }
    }

    // MARK: - Fan

    /// Sized to the arc's bounding box so the items are inside their own view
    /// and reliably take taps. The whole thing lives in an overlay, so the
    /// space it claims costs the content nothing.
    private var fan: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                button(action) { isOpen = false }
                    .offset(offset(at: index))
                    .opacity(isOpen ? 1 : 0)
                    // Scaled from nothing so a closed fan reads as tucked
                    // behind the trigger rather than merely invisible.
                    .scaleEffect(isOpen ? 1 : 0.4, anchor: .bottomTrailing)
                    .allowsHitTesting(isOpen)
                    .animation(animation(forItem: index), value: isOpen)
            }
            trigger
        }
        .frame(
            width: radius + prominentDiameter,
            height: radius + prominentDiameter,
            alignment: .bottomTrailing
        )
    }

    /// Where item `index` sits relative to the trigger. Evenly spread along
    /// the arc; a single item goes straight up rather than to one end of it.
    private func offset(at index: Int) -> CGSize {
        guard isOpen else { return .zero }
        let degrees: Double = if actions.count == 1 {
            arcStart
        } else {
            arcStart + (arcEnd - arcStart) * Double(index) / Double(actions.count - 1)
        }
        let radians = degrees * .pi / 180
        // Negative height because SwiftUI's y grows downward and the fan opens
        // upward.
        return CGSize(
            width: radius * cos(radians),
            height: -radius * sin(radians)
        )
    }

    /// Staggered outward, so the fan unfolds rather than snapping open as a
    /// block. Reduce Motion collapses the stagger and the spring both: the
    /// items still appear, they just stop travelling to get there.
    private func animation(forItem index: Int) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        let step = 0.035 * Double(isOpen ? index : actions.count - 1 - index)
        return .spring(response: 0.34, dampingFraction: 0.72).delay(step)
    }

    private var trigger: some View {
        Button {
            if reduceMotion {
                isOpen.toggle()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isOpen.toggle() }
            }
        } label: {
            Image(systemName: "plus")
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.fabGlyph.resolve(scheme))
                // The plus turns into a cross rather than swapping glyph, so
                // the control reads as one thing in two states.
                .rotationEffect(.degrees(isOpen ? 45 : 0))
                .frame(width: prominentDiameter, height: prominentDiameter)
                .background(
                    Circle()
                        .fill(LifeOSTokens.fabFill.resolve(scheme))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.2),
                                radius: 10, y: 4)
                )
        }
        .accessibilityLabel(isOpen ? "Hide actions" : "Show actions")
        .accessibilityAddTraits(isOpen ? [.isSelected] : [])
    }

    // MARK: - The button, written once

    private func button(_ action: QuickAction, onTap: @escaping () -> Void = {}) -> some View {
        let filled = isFilled(action)
        let size = self.size(prominent: action.isProminent)
        return Button {
            onTap()
            action.action()
        } label: {
            if filled, let word = action.shortLabel {
                // The labelled form: an ink capsule rather than a circle, so
                // the one action that matters reads as a button with a name.
                Label(word, systemImage: action.systemImage)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.fabGlyph.resolve(scheme))
                    .padding(.horizontal, 12)
                    .frame(height: size)
                    .background(Capsule().fill(LifeOSTokens.fabFill.resolve(scheme)))
            } else if arrangement == .row, let word = action.shortLabel {
                // A named action that is not the prominent one: an outlined
                // word, the way EditorialTag draws an outlined word, so LIFO
                // reads as LIFO rather than as a speech-bubble guess.
                Text(word)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.horizontal, 12)
                    .frame(height: size)
                    .overlay(Capsule().strokeBorder(LifeOSTokens.primaryText.resolve(scheme).opacity(0.5), lineWidth: 1))
            } else {
                Image(systemName: action.systemImage)
                    .font(arrangement == .row ? LifeOSType.body.weight(.medium) : LifeOSType.sectionTitle)
                    .foregroundStyle(
                        filled
                        ? LifeOSTokens.fabGlyph.resolve(scheme)
                        : LifeOSTokens.primaryText.resolve(scheme)
                    )
                    .frame(width: size, height: size)
                    .background(background(prominent: filled))
            }
        }
        .accessibilityLabel(action.label)
    }

    private func size(prominent: Bool) -> CGFloat {
        switch arrangement {
        case .row: rowDiameter
        case .fan: diameter
        }
    }

    /// Prominence is a row idea only.
    ///
    /// In the fan the trigger is already the filled circle, and a second one
    /// out on the arc reads as a second trigger rather than as the important
    /// action. Uniform glass items also keep the arc evenly spaced, since one
    /// item four points wider than its neighbours pushes into them.
    private func isFilled(_ action: QuickAction) -> Bool {
        arrangement == .row && action.isProminent
    }

    /// Glass in the fan, where the buttons float over somebody's content and
    /// need to separate from it. Bare in the row, where the bar already
    /// separates them and a circle around every glyph would be three chips of
    /// chrome in a place the system draws none.
    @ViewBuilder
    private func background(prominent: Bool) -> some View {
        if prominent {
            Circle()
                .fill(LifeOSTokens.fabFill.resolve(scheme))
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.2),
                        radius: arrangement == .row ? 6 : 10,
                        y: arrangement == .row ? 2 : 4)
        } else if arrangement == .fan {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().strokeBorder(
                        Color.white.opacity(scheme == .dark ? 0.2 : 0.55),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 10, y: 4)
        }
    }
}
