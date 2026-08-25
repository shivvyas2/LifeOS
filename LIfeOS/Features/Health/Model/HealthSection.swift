import Foundation
import DesignSystem

/// The Health tab's two halves: how the body is doing, and what it did.
enum HealthSection: String, CaseIterable, Identifiable {
    case health, fitness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health:  "Health"
        case .fitness: "Fitness"
        }
    }

    var hue: ModuleHue {
        switch self {
        case .health:  .body
        case .fitness: .activity
        }
    }
}
