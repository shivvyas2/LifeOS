import SwiftUI

/// The coach's backdrop: onyx falling through blue slate into an alabaster
/// bloom low on the leading edge. Fixed rather than scheme-resolved; the
/// coach is an immersive dark surface in both appearances, so the screen
/// that uses this must also resolve its tokens as dark.
public struct SlateAurora: View {
    public init() {}

    public var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.55], [0.55, 0.5], [1.0, 0.45],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                .onyx, .onyx, .onyx,
                .slateDeep, .blueSlate, .blueSlate,
                .alabaster, .slateHaze, .blueSlate,
            ]
        )
    }
}

private extension Color {
    /// #0A0A0A
    static let onyx = Color(red: 0.039, green: 0.039, blue: 0.039)
    /// #536878
    static let blueSlate = Color(red: 0.325, green: 0.408, blue: 0.471)
    /// #E5E4E2
    static let alabaster = Color(red: 0.898, green: 0.894, blue: 0.886)
    /// Blue slate pulled toward onyx, so the leading edge keeps depth where
    /// the alabaster bloom has not reached.
    static let slateDeep = Color(red: 0.16, green: 0.21, blue: 0.26)
    /// Alabaster pulled toward slate: the seam between the bloom and the band.
    static let slateHaze = Color(red: 0.62, green: 0.65, blue: 0.68)
}

#Preview {
    SlateAurora().ignoresSafeArea()
}
