import SwiftUI
import DesignSystem
import Persistence

/// Colour for the eight note accents.
///
/// Lives in the app target rather than in `DesignSystem`, because the accent
/// *name* is a persistence concern and `DesignSystem` deliberately depends on
/// nothing. Joining the two here costs one file and keeps both packages able to
/// build alone.
///
/// Three tones per accent, and they are not shades of one another. `fill` is
/// the card, and has to stay quiet enough that eight of them on one screen read
/// as a set. `dot` is the four-point sidebar mark, which at that size needs
/// real saturation or it disappears. `ink` is text on `fill`, and is the only
/// one contrast is actually measured against.
enum NoteAccentPalette {

    static func fill(_ accent: NoteAccent, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark(accent).fill : light(accent).fill
    }

    static func dot(_ accent: NoteAccent, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark(accent).dot : light(accent).dot
    }

    static func ink(_ accent: NoteAccent, _ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark(accent).ink : light(accent).ink
    }

    /// A hairline on top of `fill`. Pure black at low alpha rather than a
    /// darker tint of the accent: eight separate border colours make the grid
    /// noisier without making any single card clearer.
    static func edge(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.35 : 0.06)
    }

    private static func light(_ accent: NoteAccent) -> (fill: Color, dot: Color, ink: Color) {
        switch accent {
        case .sage:  (Color(red: 0.87, green: 0.93, blue: 0.87), Color(red: 0.35, green: 0.62, blue: 0.42), Color(red: 0.13, green: 0.25, blue: 0.16))
        case .sand:  (Color(red: 0.97, green: 0.93, blue: 0.81), Color(red: 0.83, green: 0.66, blue: 0.24), Color(red: 0.30, green: 0.23, blue: 0.06))
        case .sky:   (Color(red: 0.86, green: 0.91, blue: 0.97), Color(red: 0.29, green: 0.53, blue: 0.83), Color(red: 0.11, green: 0.20, blue: 0.33))
        case .lilac: (Color(red: 0.90, green: 0.87, blue: 0.97), Color(red: 0.52, green: 0.41, blue: 0.83), Color(red: 0.20, green: 0.15, blue: 0.34))
        case .clay:  (Color(red: 0.98, green: 0.89, blue: 0.82), Color(red: 0.84, green: 0.46, blue: 0.25), Color(red: 0.33, green: 0.17, blue: 0.08))
        case .rose:  (Color(red: 0.98, green: 0.88, blue: 0.90), Color(red: 0.82, green: 0.38, blue: 0.50), Color(red: 0.33, green: 0.13, blue: 0.18))
        case .moss:  (Color(red: 0.91, green: 0.94, blue: 0.83), Color(red: 0.53, green: 0.63, blue: 0.29), Color(red: 0.19, green: 0.25, blue: 0.09))
        case .slate: (Color(red: 0.91, green: 0.91, blue: 0.90), Color(red: 0.45, green: 0.46, blue: 0.46), Color(red: 0.16, green: 0.17, blue: 0.17))
        }
    }

    /// Dark mode is not the light palette dimmed. The card becomes a deep,
    /// desaturated ground and the ink becomes a light tint of the same hue, so
    /// the accent still identifies the card without glowing on a black canvas.
    private static func dark(_ accent: NoteAccent) -> (fill: Color, dot: Color, ink: Color) {
        switch accent {
        case .sage:  (Color(red: 0.10, green: 0.18, blue: 0.13), Color(red: 0.45, green: 0.75, blue: 0.53), Color(red: 0.79, green: 0.91, blue: 0.82))
        case .sand:  (Color(red: 0.21, green: 0.17, blue: 0.07), Color(red: 0.91, green: 0.75, blue: 0.34), Color(red: 0.95, green: 0.89, blue: 0.75))
        case .sky:   (Color(red: 0.09, green: 0.15, blue: 0.25), Color(red: 0.44, green: 0.66, blue: 0.93), Color(red: 0.81, green: 0.88, blue: 0.97))
        case .lilac: (Color(red: 0.15, green: 0.12, blue: 0.26), Color(red: 0.65, green: 0.55, blue: 0.93), Color(red: 0.87, green: 0.83, blue: 0.97))
        case .clay:  (Color(red: 0.24, green: 0.13, blue: 0.07), Color(red: 0.93, green: 0.58, blue: 0.35), Color(red: 0.97, green: 0.85, blue: 0.77))
        case .rose:  (Color(red: 0.24, green: 0.11, blue: 0.15), Color(red: 0.92, green: 0.51, blue: 0.63), Color(red: 0.97, green: 0.84, blue: 0.87))
        case .moss:  (Color(red: 0.14, green: 0.18, blue: 0.08), Color(red: 0.66, green: 0.77, blue: 0.39), Color(red: 0.87, green: 0.92, blue: 0.78))
        case .slate: (Color(red: 0.16, green: 0.16, blue: 0.16), Color(red: 0.62, green: 0.63, blue: 0.63), Color(red: 0.88, green: 0.88, blue: 0.88))
        }
    }
}

/// The serif the notes surface titles in.
///
/// The rest of the app is system sans throughout, on purpose: it is a
/// dashboard, and a dashboard reads better in one neutral face. Notes are the
/// one place someone writes prose, and a serif at display sizes is what makes
/// the shelf feel like a library rather than another settings screen. It is
/// used for titles only, never for body text or controls.
extension Font {
    static func noteSerif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
