import SwiftUI

/// Items that arrive one after another rather than all at once.
///
/// Each item fades in and rises a few points, a beat after the one before.
/// The cascade is what tells the eye a list is a list of separate things,
/// and the order it reads them in. It runs when the view first appears, so
/// a pull to refresh redraws the figures in place and a new identity (a tab
/// switch) deals the list in again.
///
/// The delay stops growing after `cap` items: a ledger of forty rows should
/// not take two seconds to finish arriving. With Reduce Motion on the items
/// fade without moving.
extension View {
    public func staggeredEntrance(index: Int, step: Double = 0.04, cap: Int = 8) -> some View {
        modifier(StaggeredEntrance(delay: Double(min(max(index, 0), cap)) * step))
    }
}

private struct StaggeredEntrance: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.32).delay(delay)) {
                    shown = true
                }
            }
    }
}

/// A row that answers the finger: an ink wash while pressed.
///
/// `.plain` draws nothing on press, so a tappable row and a row of plain
/// facts look the same until something opens. The wash runs a little past
/// the row's edges so it reads as the row lighting up, not as a box.
public struct EditorialRowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressedRow(configuration: configuration)
    }

    private struct PressedRow: View {
        let configuration: Configuration
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(LifeOSTokens.primaryText.resolve(scheme).opacity(configuration.isPressed ? 0.06 : 0))
                        .padding(.horizontal, -Space.half)
                }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == EditorialRowButtonStyle {
    /// A tappable row on the paper: no chrome at rest, a wash when pressed.
    public static var editorialRow: EditorialRowButtonStyle { EditorialRowButtonStyle() }
}
