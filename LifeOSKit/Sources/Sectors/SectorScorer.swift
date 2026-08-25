import Persistence

/// One sector's rule.
///
/// A conforming type is built from values that have already been fetched, not
/// from a store. That is what keeps every scoring test free of a container,
/// and it is why `evidence()` neither throws nor awaits.
public protocol SectorScorer: Sendable {
    var sector: LifeSector { get }
    func evidence() -> Evidence
}
