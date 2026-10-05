import SwiftUI
import DesignSystem

/// The six things the Money screen answers, in the order its tab strip
/// numbers them.
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
}
