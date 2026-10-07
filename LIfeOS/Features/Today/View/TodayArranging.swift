import SwiftUI
import DesignSystem

/// A row of Today while it is being arranged: it wobbles (or, with Reduce
/// Motion, wears a dashed outline), carries a minus per module, and is
/// dragged and dropped on as a whole. Its own content takes no taps, so
/// nothing is ticked or opened by accident.
struct ArrangeableModule: ViewModifier {
    let modules: [TodayModule]
    let isArranging: Bool
    let index: Int
    var onHide: (TodayModule) -> Void
    /// A module name dropped on one of this row's modules, and whether it
    /// landed in that module's lower half (after it) or upper (before).
    var onDrop: (String, TodayModule, Bool) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var wobble = false
    @State private var targeted: TodayModule?

    private var tilt: Double {
        guard isArranging, !reduceMotion else { return 0 }
        return (wobble ? 1.2 : -1.2) * (index.isMultiple(of: 2) ? 1 : -1)
    }

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isArranging)
            .overlay {
                if isArranging {
                    // Catches every touch on the row: the drag, the drop, and
                    // taps, which it swallows. One area per module, so either
                    // tile of a pair can be picked up.
                    HStack(spacing: 12) {
                        ForEach(modules, id: \.self) { module in
                            GeometryReader { proxy in
                                Color.clear
                                    .contentShape(.rect)
                                    .onTapGesture {}
                                    .draggable(module.rawValue) {
                                        Text(module.title)
                                            .font(LifeOSType.rowTitle)
                                            .padding(.horizontal, Space.x2).padding(.vertical, Space.x1)
                                            .background(LifeOSTokens.cardSurface.resolve(scheme), in: Capsule())
                                    }
                                    .dropDestination(for: String.self) { names, location in
                                        guard let name = names.first else { return false }
                                        return onDrop(name, module, location.y > proxy.size.height / 2)
                                    } isTargeted: { over in
                                        if over { targeted = module } else if targeted == module { targeted = nil }
                                    }
                                    .overlay {
                                        if targeted == module {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(LifeOSTokens.primaryText.resolve(scheme), lineWidth: 1.5)
                                        }
                                    }
                            }
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                if isArranging, reduceMotion {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Editorial.quietInk(scheme))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if isArranging {
                    HStack(spacing: Space.half) {
                        ForEach(modules, id: \.self) { module in
                            Button { onHide(module) } label: {
                                // An ink disc with a paper minus, readable on any card.
                                Image(systemName: "minus.circle.fill")
                                    .font(LifeOSType.sectionTitle)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(LifeOSTokens.canvas.resolve(scheme),
                                                     LifeOSTokens.primaryText.resolve(scheme))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hide \(module.title)")
                        }
                    }
                    .offset(x: -10, y: -10)
                }
            }
            .rotationEffect(.degrees(tilt))
            .animation(isArranging && !reduceMotion
                       ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default,
                       value: wobble)
            .onChange(of: isArranging) { _, on in wobble = on }
            .onAppear { wobble = isArranging }
    }
}

/// Under the arrangement while arranging: a chip for every hidden module, and
/// the way back to the default.
struct TodayTray: View {
    let hidden: [TodayModule]
    let isGitHubConnected: Bool
    var onAdd: (TodayModule) -> Void
    var onConnectGitHub: () -> Void
    var onReset: () -> Void
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            EditorialSectionHeader(title: "Add to Today")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Space.x1, alignment: .leading)],
                      alignment: .leading, spacing: Space.x1) {
                ForEach(hidden, id: \.self) { module in
                    if module == .github, !isGitHubConnected {
                        Button("Connect GitHub", action: onConnectGitHub)
                            .buttonStyle(.editorial(.secondary, size: .compact))
                    } else {
                        Button("+ \(module.title)") { onAdd(module) }
                            .buttonStyle(.editorial(.secondary, size: .compact))
                            .accessibilityLabel("Add \(module.title)")
                            .draggable(module.rawValue)
                    }
                }
            }
            Button("Reset to default") { confirmReset = true }
                .buttonStyle(.editorial(.quiet, size: .compact))
                .confirmationDialog("Reset Today to its default arrangement?", isPresented: $confirmReset,
                                    titleVisibility: .visible) {
                    Button("Reset to default", role: .destructive, action: onReset)
                }
        }
    }
}

/// Shown until the first arrange, or until closed.
struct TodayArrangeHint: View {
    var onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Text("Long-press anything to rearrange Today.")
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(Editorial.quietInk(scheme))
                .accessibilityLabel("Dismiss")
        }
        .editorialCard()
    }
}
