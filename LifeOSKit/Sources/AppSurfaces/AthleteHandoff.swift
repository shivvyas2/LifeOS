import Foundation

/// What the Watch does with the athlete profile the phone sends in its
/// `configure` command.
///
/// A phone-started workout reaches the Watch before any profile the phone
/// saved has, or the Watch never received one at all, and the Watch reads
/// its profile exactly once, when the workout starts. So the profile rides
/// along with `configure`, and this decides, without touching sensors or
/// storage, whether it replaces the Watch's own and whether swing analysis
/// should start on a badminton workout that began without it.
public enum AthleteHandoff {
    public struct Decision: Equatable, Sendable {
        /// The profile to keep, or nil when the Watch's own stands.
        public var adopt: ActivityAthleteProfile?
        /// True when a badminton workout that is not analyzing swings should
        /// start now, with the adopted profile.
        public var startsSwingAnalysis: Bool
        public init(adopt: ActivityAthleteProfile?, startsSwingAnalysis: Bool) {
            self.adopt = adopt; self.startsSwingAnalysis = startsSwingAnalysis
        }
    }

    public static func decide(incoming: ActivityAthleteProfile?, current: ActivityAthleteProfile?,
                              activityName: String, analyzing: Bool) -> Decision {
        guard let incoming, incoming.isValid,
              current.map({ incoming.updatedAt > $0.updatedAt }) ?? true else {
            return Decision(adopt: nil, startsSwingAnalysis: false)
        }
        let starts = !analyzing && activityName == "Badminton" && incoming.canAnalyzeSwings
        return Decision(adopt: incoming, startsSwingAnalysis: starts)
    }
}
