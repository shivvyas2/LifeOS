#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias ContentState = LiveSessionReadout
    public let sessionID: UUID
    public let name: String
    public let icon: String
    public init(sessionID: UUID, name: String, icon: String) {
        self.sessionID = sessionID; self.name = name; self.icon = icon
    }
}
#endif
