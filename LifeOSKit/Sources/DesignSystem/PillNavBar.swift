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

/// The app's navigation: a floating capsule of circular icon buttons, the
/// selected one a dark filled circle. Replaces the system tab bar, so it owns
/// what the system gave free: 44pt+ targets, labels, and selection traits.
public struct PillNavBar<Tab: Hashable>: View {
    @Binding private var selection: Tab
    private let items: [PillNavItem<Tab>]
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Tab>, items: [PillNavItem<Tab>]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected
                            ? LifeOSTokens.canvas.resolve(scheme)
                            : LifeOSTokens.secondaryText.resolve(scheme))
                        .frame(width: 52, height: 52)
                        .background {
                            if isSelected {
                                Circle().fill(LifeOSTokens.primaryText.resolve(scheme))
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(
            Capsule().fill(LifeOSTokens.cardSurface.resolve(scheme))
                .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.12), radius: 16, y: 6)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}

#Preview {
    @Previewable @State var tab = 0
    ZStack(alignment: .bottom) {
        LifeOSTokens.canvas.resolve(.light)
        PillNavBar(selection: $tab, items: [
            PillNavItem(value: 0, systemImage: "circle.grid.3x3.fill", label: "Today"),
            PillNavItem(value: 1, systemImage: "heart.fill", label: "Health"),
            PillNavItem(value: 2, systemImage: "dollarsign", label: "Money"),
            PillNavItem(value: 3, systemImage: "checklist", label: "Plan"),
        ])
        .padding(.bottom, 20)
    }
}
