import Foundation

/// Sleep arithmetic, kept separate from the client so it is testable without a
/// network layer and reviewable on its own.
enum WhoopSleepMath {
    /// Time actually asleep, in minutes.
    ///
    /// Prefers summing the stages, which is the direct measure. Falls back to
    /// time in bed minus time awake when the stage breakdown is absent, so a
    /// partial payload degrades rather than nulling the field.
    static func asleepMinutes(from stages: WhoopDTOs.SleepRecord.Score.Stages?) -> Int? {
        guard let stages else { return nil }

        let light = stages.total_light_sleep_time_milli
        let rem = stages.total_rem_sleep_time_milli
        let sws = stages.total_slow_wave_sleep_time_milli

        if light != nil || rem != nil || sws != nil {
            let total = (light ?? 0) + (rem ?? 0) + (sws ?? 0)
            return Int(total / 60_000)
        }

        guard let inBed = stages.total_in_bed_time_milli else { return nil }
        let awake = stages.total_awake_time_milli ?? 0
        return Int(max(inBed - awake, 0) / 60_000)
    }

    static func minutes(fromMilliseconds milli: Double?) -> Int? {
        milli.map { Int($0 / 60_000) }
    }
}
