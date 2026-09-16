import HealthKit
import AppSurfaces

extension ActivityType {
    /// The catalog stores the raw value so the package stays free of
    /// HealthKit. A value HealthKit rejects is a catalog bug the native
    /// check reports; at runtime the session still starts, as Other.
    var healthType: HKWorkoutActivityType { HKWorkoutActivityType(rawValue: healthRawValue) ?? .other }
}

extension ActivityCatalog {
    static let walk = type(named: "Walk")!
    static let run = type(named: "Run")!
    static let cycle = type(named: "Cycle")!
    static let strength = type(named: "Strength")!
    static let yoga = type(named: "Yoga")!
}
