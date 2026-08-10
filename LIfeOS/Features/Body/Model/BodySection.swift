import Foundation
import DesignSystem

/// The Body tab covers everything about the body, not just fitness: movement,
/// weight, recovery and wellness live behind one tab so the tab bar stays free
/// for the other life domains.
enum BodySection: String, CaseIterable, Identifiable {
    case activity, weight, recovery, wellness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: "Activity"
        case .weight:   "Weight"
        case .recovery: "Recovery"
        case .wellness: "Wellness"
        }
    }

    /// Each section keeps its own hue, so the canvas re-tints as you switch.
    var hue: ModuleHue {
        switch self {
        case .activity: .activity
        case .weight:   .body
        case .recovery: .recovery
        case .wellness: .habits
        }
    }
}
