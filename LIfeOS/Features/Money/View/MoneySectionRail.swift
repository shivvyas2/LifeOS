import SwiftUI
import DesignSystem

/// The six things this screen answers.
///
/// One tab per question rather than one long scroll, because the questions are
/// asked separately: "what came in" and "what should I cancel" are different
/// visits, and a single column that answers both makes each one a scroll past
/// the other.
enum MoneySection: String, CaseIterable, Identifiable {
    case flow
    case categories
    case repeating
    case goal
    case pressure
    case ledger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flow:       "In and out"
        case .categories: "Where it went"
        case .repeating:  "Every month"
        case .goal:       "Saving for"
        case .pressure:   "What hurts"
        case .ledger:     "Recent"
        }
    }

    /// The rail is too narrow for the full title, and an icon alone is a
    /// guessing game. A single short word under the glyph is what makes the
    /// rail readable without opening anything.
    var shortTitle: String {
        switch self {
        case .flow:       "Flow"
        case .categories: "Spend"
        case .repeating:  "Repeat"
        case .goal:       "Goal"
        case .pressure:   "Hurts"
        case .ledger:     "Recent"
        }
    }

    var systemImage: String {
        switch self {
        case .flow:       "arrow.left.arrow.right"
        case .categories: "chart.pie.fill"
        case .repeating:  "arrow.clockwise"
        case .goal:       "target"
        case .pressure:   "exclamationmark.triangle.fill"
        case .ledger:     "list.bullet"
        }
    }

    var tone: AdaptiveColor {
        switch self {
        case .flow:       MoneyPalette.sage
        case .categories: MoneyPalette.mist
        case .repeating:  MoneyPalette.mint
        case .goal:       MoneyPalette.butter
        case .pressure:   MoneyPalette.clay
        case .ledger:     MoneyPalette.stone
        }
    }
}

/// The section picker for the Money screen.
///
/// Two shapes, and which one appears is not a style preference. On a phone the
/// app's own nav bar is a floating pill along the bottom, so the side is free
/// and a vertical rail is the right call: the content is full-bleed colour
/// bands, and a horizontal strip would need its own background and read as a
/// second, competing header.
///
/// On iPad that same nav bar stands on end against the left edge. A second
/// vertical rail beside it is two parallel bars of chrome doing unrelated jobs,
/// which is exactly as confusing as it sounds: the reader has to work out which
/// bar changes the tab and which changes the section. So on a regular width
/// this lies down into a row of chips above the content, and the screen keeps
/// one vertical bar.
struct MoneySectionRail: View {
    @Binding var selection: MoneySection
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layout) private var layout
    @Namespace private var marker

    private static let width: CGFloat = 62

    var body: some View {
        if layout.isRegular { chips } else { rail }
    }

    /// iPad: a horizontal row, so the app's left nav rail stays the only
    /// vertical bar on screen.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.half) {
                ForEach(MoneySection.allCases) { section in
                    let isSelected = section == selection
                    Button { select(section) } label: {
                        HStack(spacing: Space.half + 2) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                            // The full title here, not the rail's clipped one:
                            // a horizontal chip has the room, and "Where it
                            // went" says what "Spend" only gestures at.
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(MoneyPalette.ink.resolve(scheme)
                            .opacity(isSelected ? 1 : 0.45))
                        .padding(.vertical, 9)
                        .padding(.horizontal, Space.x2)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(section.tone.resolve(scheme))
                                    .matchedGeometryEffect(id: "rail", in: marker)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.title)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(Space.half)
        }
        .scrollIndicators(.hidden)
        .background(
            Capsule().fill(MoneyPalette.ink.resolve(scheme).opacity(scheme == .dark ? 0.10 : 0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Money sections")
    }

    private func select(_ section: MoneySection) {
        if reduceMotion {
            selection = section
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                selection = section
            }
        }
    }

    /// iPhone: a vertical rail down the free side.
    private var rail: some View {
        VStack(spacing: 2) {
            ForEach(MoneySection.allCases) { section in
                let isSelected = section == selection

                Button { select(section) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                        Text(section.shortTitle)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.3)
                    }
                    .foregroundStyle(MoneyPalette.ink.resolve(scheme)
                        .opacity(isSelected ? 1 : 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                .fill(section.tone.resolve(scheme))
                                // One shared id, so the block slides between
                                // sections instead of cross-fading in place.
                                .matchedGeometryEffect(id: "rail", in: marker)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.vertical, Space.half)
        .padding(.horizontal, Space.half)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(MoneyPalette.ink.resolve(scheme).opacity(scheme == .dark ? 0.10 : 0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Money sections")
    }
}
