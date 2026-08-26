import SwiftUI

/// The app's type scale.
///
/// Before this existed there were 376 hand-written `.system(size:weight:)`
/// calls across 28 distinct sizes between 9 and 104, three of which (13, 14 and
/// 15) accounted for 178 of them. Nobody chose that: it is what happens when
/// every screen picks its own number, and the drift is invisible until two
/// screens sit side by side.
///
/// Nine text steps and three numeral steps. Fewer than the app had, on purpose:
/// a scale only does its job if the steps are far enough apart that picking the
/// wrong one is obvious.
///
/// # Families
///
/// Two, each with exactly one job.
///
/// **Text is the system sans, always.** Every word in the app, on every screen.
///
/// **Numerals are rounded, and only numerals.** Rounded digits are genuinely
/// easier to read at a glance, which is the whole reason the money screen
/// reached for the face in the first place. It is never used for words: a
/// rounded label next to a sans label is the drift this type exists to stop.
///
/// A serif was briefly the notes tab's title face and is deliberately gone. It
/// looked right on that one screen and wrong beside every other.
public enum LifeOSType {

    // MARK: - Text

    /// Uppercase section markers. Tracked, because capitals set tight are hard
    /// to read; use `.tracking(0.6)` alongside.
    public static let eyebrow = Font.system(size: 11, weight: .semibold)

    /// Timestamps, counts, and the small print under a figure.
    public static let caption = Font.system(size: 12, weight: .regular)

    /// The workhorse for dense repeated rows: list cells, chips, sidebar
    /// entries. Medium rather than regular because it is usually set in a
    /// secondary colour, and regular at 13 in grey is thin.
    public static let label = Font.system(size: 13, weight: .medium)

    /// Supporting copy: the sentence under a heading, a card's explanation.
    public static let secondary = Font.system(size: 15, weight: .regular)

    /// Reading text. Note blocks, journal entries, anything someone actually
    /// reads a paragraph of.
    public static let body = Font.system(size: 17, weight: .regular)

    /// The title of a row or a card, sitting on top of its own content.
    public static let rowTitle = Font.system(size: 15, weight: .semibold)

    /// A section heading inside a screen.
    public static let sectionTitle = Font.system(size: 20, weight: .semibold)

    /// The heading a screen is named by.
    public static let screenTitle = Font.system(size: 24, weight: .bold)

    /// The largest words in the app. One per screen at most.
    public static let display = Font.system(size: 34, weight: .bold)

    // MARK: - Numerals

    /// A figure inside a tile, beside its label.
    public static let numeral = Font.system(size: 28, weight: .bold, design: .rounded)

    /// The one figure a screen is about.
    public static let numeralLarge = Font.system(size: 44, weight: .bold, design: .rounded)

    /// Hero numerals size themselves to the space they are given, so this takes
    /// the size rather than fixing it. Still the rounded face, still bold, so a
    /// hero and a tile figure are recognisably the same number in two sizes.
    ///
    /// The only place a size may be passed in. Everything else picks a step.
    public static func numeral(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Monospace

    /// Machine output: an identifier, a raw payload, a diagnostic. Never used
    /// for anything a person wrote.
    public static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, design: .monospaced)
    }
}

#if canImport(UIKit)
import UIKit

/// The same scale, as `UIFont`.
///
/// The note editor draws its blocks in a `UITextView`, which cannot take a
/// SwiftUI `Font`. Without this the editor would carry a second set of sizes
/// that happened to look close to the first, and the two would drift the moment
/// either was touched. Every value here reads off the same numbers as the
/// SwiftUI scale above, so changing a step changes both.
public extension LifeOSType {
    enum UIKitScale {
        public static let bodySize: CGFloat = 17
        public static let secondarySize: CGFloat = 15
        public static let sectionTitleSize: CGFloat = 20
        public static let screenTitleSize: CGFloat = 24

        public static let body = UIFont.systemFont(ofSize: bodySize, weight: .regular)
        public static let secondary = UIFont.systemFont(ofSize: secondarySize, weight: .regular)
        public static let sectionTitle = UIFont.systemFont(ofSize: sectionTitleSize, weight: .semibold)
        public static let screenTitle = UIFont.systemFont(ofSize: screenTitleSize, weight: .bold)
        /// Reading text set in bold, for a heading one step above the body
        /// without a size change.
        public static let bodyStrong = UIFont.systemFont(ofSize: bodySize, weight: .semibold)
        public static let mono = UIFont.monospacedSystemFont(ofSize: secondarySize, weight: .regular)
    }
}
#endif
