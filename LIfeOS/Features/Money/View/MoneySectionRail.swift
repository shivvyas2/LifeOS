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

/// The vertical tab rail down the side of the Money screen.
///
/// Down the side rather than across the top because the content is full-bleed
/// colour bands: a horizontal tab strip would need its own background and
/// would read as a second, competing header. A narrow rail lets each band run
/// to the right edge and gives the selected section a block of its own colour
/// to sit against, which is the same device the bands themselves use.
struct MoneySectionRail: View {
    @Binding var selection: MoneySection
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var marker

    private static let width: CGFloat = 62

    var body: some View {
        VStack(spacing: 2) {
            ForEach(MoneySection.allCases) { section in
                let isSelected = section == selection

                Button {
                    if reduceMotion {
                        selection = section
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            selection = section
                        }
                    }
                } label: {
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
