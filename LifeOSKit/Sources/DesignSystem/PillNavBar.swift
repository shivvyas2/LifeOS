import SwiftUI

/// One tab in the floating pill bar.
public struct PillNavItem<Tab: Hashable>: Identifiable {
    public let value: Tab
    public let systemImage: String
    public let label: String

    public var id: Tab { value }

    public init(value: Tab, systemImage: String, label: String) {
        self.value = value
        self.systemImage = systemImage
        self.label = label
    }
}

/// The app's navigation: a floating ink capsule in which every tab shows its
/// icon and its name, the selected one on a paper pill. Replaces the system
/// tab bar, so it owns what the system gave free: 44pt+ targets, labels, and
/// selection traits.
///
/// Labels are visible, not only spoken. The bar used to be icon circles alone,
/// and two of its glyphs were near-identical grids: a person had to tap to
/// find out where a tab went, which is the one thing a tab bar must never ask.
///
/// One component in two orientations rather than two components: a phone gets
/// the horizontal bar along the bottom, a wide pane gets the same capsule stood
/// on end as a left rail. Splitting them would leave the pill's styling defined
/// in two places, which is exactly how the two would drift apart.
///
/// Navigation only, in both orientations. The coach and quick-log buttons float
/// free of the bar on every size, so the bar never has to explain why two of its
/// circles do not select a tab.
public struct PillNavBar<Tab: Hashable>: View {
    @Binding private var selection: Tab
    private let items: [PillNavItem<Tab>]
    private let axis: Axis
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Tab>, items: [PillNavItem<Tab>], axis: Axis = .horizontal) {
        self._selection = selection
        self.items = items
        self.axis = axis
    }

    public var body: some View {
        stack {
            ForEach(items) { item in
                button(for: item)
            }
        }
        .padding(6)
        .background(
            // Ink in light mode, a raised charcoal in dark: the bar is always
            // the darkest thing on screen, so the paper pill inside it is
            // always the brightest, whichever scheme is on.
            Capsule().fill(scheme == .dark ? Color(white: 0.16) : LifeOSTokens.primaryText.resolve(.light))
                .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 16, y: 6)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        switch axis {
        case .horizontal: HStack(spacing: 6, content: content)
        case .vertical: VStack(spacing: 6, content: content)
        }
    }

    private func button(for item: PillNavItem<Tab>) -> some View {
        let isSelected = item.value == selection
        let paper = LifeOSTokens.canvas.resolve(.light)
        let ink = LifeOSTokens.primaryText.resolve(.light)
        return Button {
            selection = item.value
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(LifeOSType.label.weight(.semibold))
                    .frame(height: 18)
                Text(item.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? ink : paper.opacity(0.62))
            .frame(minWidth: 56, minHeight: 52)
            .padding(.horizontal, 4)
            .background {
                if isSelected {
                    Capsule().fill(paper)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Bar") {
    @Previewable @State var tab = 0
    ZStack(alignment: .bottom) {
        LifeOSTokens.canvas.resolve(.light)
        PillNavBar(selection: $tab, items: .preview)
            .padding(.bottom, 20)
    }
}

#Preview("Rail") {
    @Previewable @State var tab = 0
    ZStack(alignment: .leading) {
        LifeOSTokens.canvas.resolve(.light)
        PillNavBar(selection: $tab, items: .preview, axis: .vertical)
            .padding(.leading, 20)
    }
}

private extension Array {
    static var preview: [PillNavItem<Int>] {
        [
            PillNavItem(value: 0, systemImage: "circle.grid.3x3.fill", label: "Today"),
            PillNavItem(value: 1, systemImage: "heart.fill", label: "Health"),
            PillNavItem(value: 2, systemImage: "dollarsign", label: "Money"),
            PillNavItem(value: 3, systemImage: "checklist", label: "Plan"),
        ]
    }
}
