import Foundation
import Persistence

/// The one decision, made once, about which sectors have a full tab
/// elsewhere in the app, beyond the score history every sector's detail
/// screen shows.
///
/// Before this project, `RootView` routed Body, Money and Mission to their
/// existing Health, Money and Plan tabs so no sector had two homes. This
/// project keeps that link as an extra row on those three sectors' detail
/// screens, but the "which three" question is now decided in exactly one
/// place. `LifeBoardScreen` reads it to decide whether a sector's detail
/// screen gets an "Open ..." row at all; `RootView` reads it too, to map that
/// answer onto its own private tab selection. Neither redecides it with its
/// own case list.
public extension LifeSector {
    var ownsTab: Bool {
        switch self {
        case .body, .money, .mission: true
        case .family, .romance, .soul, .friends, .growth, .mind: false
        }
    }
}
