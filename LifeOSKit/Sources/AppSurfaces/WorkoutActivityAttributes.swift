#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var elapsed: TimeInterval
        public var runningSince: Date?
        public init(elapsed: TimeInterval, runningSince: Date?) {
            self.elapsed = elapsed; self.runningSince = runningSince
        }
        public var timerAnchor: Date? { runningSince?.addingTimeInterval(-elapsed) }
    }
    public let sessionID: UUID
    public let name: String
    public let icon: String
    public init(sessionID: UUID, name: String, icon: String) {
        self.sessionID = sessionID; self.name = name; self.icon = icon
    }
}
#endif
