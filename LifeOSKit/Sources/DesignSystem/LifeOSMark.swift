import SwiftUI

/// The LifeOS mark: the accent-tinted hexagon grid that heads the intro,
/// sign-up and first-run screens.
///
/// LIFO speaks with the same mark everywhere it appears, so a coach header, a
/// reply label, an insight card and an inbox row all read as the one voice the
/// user met on the sign-up screen. Nothing LIFO says wears a generic sparkle.
public enum LifeOSMark {
    /// The SF Symbol behind the mark, for `Label` and `Image(systemName:)`
    /// call sites that set their own font and colour.
    public static let symbol = "circle.hexagongrid.fill"
}
