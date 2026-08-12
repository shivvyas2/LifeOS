import Foundation

struct ActivitySnapshot: Equatable {
    var steps: Int?
    var exerciseMinutes: Int?
    var activeEnergyKcal: Double?
    var restingHR: Double?

    /// The day's sessions, oldest first. Empty on most days, which is why the
    /// view renders nothing at all rather than an empty frame.
    var workouts: [WorkoutSummary] = []
}

/// One Whoop workout, flattened for display so the view never touches SwiftData.
struct WorkoutSummary: Equatable, Identifiable {
    let id: String
    let sport: String
    let durationMinutes: Int
    let strain: Double?
    let averageHR: Double?
    let distanceMeters: Double?
    /// Whoop reports how much of the session it captured. A workout recorded at
    /// 40% is not an easy workout, and letting a low strain speak for it would
    /// say exactly that.
    let percentRecorded: Double?

    var isPartlyRecorded: Bool {
        guard let percentRecorded else { return false }
        return percentRecorded < 95
    }

    var duration: String {
        durationMinutes < 60
            ? "\(durationMinutes)m"
            : "\(durationMinutes / 60)h \(durationMinutes % 60)m"
    }

    /// Kilometres to one decimal. Nil below 100m, where a distance is noise
    /// from a workout that was not a distance workout.
    var distance: String? {
        guard let distanceMeters, distanceMeters >= 100 else { return nil }
        return String(format: "%.1f km", distanceMeters / 1000)
    }

    /// Sport names arrive lowercased from Whoop.
    var displaySport: String { sport.prefix(1).uppercased() + sport.dropFirst() }
}
