import SwiftUI

/// The user's appearance choice. `system` is nil so SwiftUI keeps following
/// the device; light and dark pin the whole tree.
public enum ColorSchemePreference: String, CaseIterable, Sendable, Hashable {
    case system, light, dark

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    public var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
}
