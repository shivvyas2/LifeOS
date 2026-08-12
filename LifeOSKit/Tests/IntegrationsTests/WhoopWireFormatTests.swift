import Testing
import Foundation
@testable import Integrations

/// Fixtures captured from a live Whoop v2 response on 2026-08-10. Field names
/// and the timestamp format are real; the values are scrubbed.
///
/// These exist because the wire format was the one part of this integration
/// that could not be verified by reasoning, and when it was finally checked
/// against the live API, the field names were right but the dates were not
/// parseable. A shape test is the only thing that catches that class of bug
/// before a user does.
@Suite struct WhoopWireFormatTests {

    private let recoveryJSON = """
    {"records":[{"cycle_id":123,"sleep_id":"a-b-c","user_id":1,
      "created_at":"2026-08-10T13:37:33.957Z","updated_at":"2026-08-10T13:37:34.000Z",
      "score_state":"SCORED",
      "score":{"user_calibrating":false,"recovery_score":66,"resting_heart_rate":54,
               "hrv_rmssd_milli":74.5,"spo2_percentage":97.2,"skin_temp_celsius":33.1}}],
     "next_token":null}
    """

    private let sleepJSON = """
    {"records":[{"id":"uuid-1","v1_id":9,"user_id":1,"cycle_id":123,
      "created_at":"2026-08-10T13:37:33.957Z","updated_at":"2026-08-10T13:37:34.000Z",
      "start":"2026-08-10T06:16:16.180Z","end":"2026-08-10T13:16:17.010Z",
      "timezone_offset":"-04:00","nap":false,"score_state":"SCORED",
      "score":{"respiratory_rate":14.2,"sleep_performance_percentage":88,
               "sleep_consistency_percentage":70,"sleep_efficiency_percentage":91,
               "sleep_needed":{"baseline_milli":27000000,"need_from_sleep_debt_milli":100,
                               "need_from_recent_strain_milli":0,"need_from_recent_nap_milli":0},
               "stage_summary":{"total_in_bed_time_milli":25200000,
                                "total_awake_time_milli":1200000,
                                "total_light_sleep_time_milli":10,"total_rem_sleep_time_milli":10,
                                "total_slow_wave_sleep_time_milli":10,"total_no_data_time_milli":0,
                                "sleep_cycle_count":5,"disturbance_count":3}}}],
     "next_token":null}
    """

    private let cycleJSON = """
    {"records":[{"id":123,"user_id":1,
      "created_at":"2026-08-10T13:37:33.957Z","updated_at":"2026-08-10T13:37:34.000Z",
      "start":"2026-08-09T10:00:00.000Z","end":null,"timezone_offset":"-04:00",
      "score_state":"SCORED",
      "score":{"strain":12.7,"kilojoule":9000.5,"average_heart_rate":70,"max_heart_rate":170}}],
     "next_token":null}
    """

    /// The regression that mattered: `.iso8601` cannot parse ".180Z", so every
    /// record failed to decode and the whole sync reported a generic failure.
    @Test func millisecondTimestampsDecode() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
        )
        let record = try #require(page.records.first)
        #expect(record.start.timeIntervalSince1970 > 0)
        #expect(record.end > record.start)
    }

    @Test func timestampsWithoutFractionalSecondsAlsoDecode() throws {
        let json = #"{"records":[{"start":"2026-08-10T06:16:16Z","end":"2026-08-10T13:16:17Z","nap":false,"score_state":"SCORED","score":null}],"next_token":null}"#
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(json.utf8)
        )
        #expect(page.records.count == 1)
    }

    @Test func recoveryFieldsMapToTheSample() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.RecoveryRecord>.self, from: Data(recoveryJSON.utf8)
        )
        let score = try #require(page.records.first?.score)
        #expect(score.recovery_score == 66)
        #expect(score.resting_heart_rate == 54)
        #expect(score.hrv_rmssd_milli == 74.5)
    }

    @Test func sleepAsleepTimeIsInBedMinusAwake() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
        )
        let stages = try #require(page.records.first?.score?.stage_summary)
        let asleepMinutes = Int(((stages.total_in_bed_time_milli ?? 0)
                               - (stages.total_awake_time_milli ?? 0)) / 60_000)
        #expect(asleepMinutes == 400)   // 25_200_000 - 1_200_000 ms = 6h 40m
    }

    @Test func cycleStrainDecodes() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.CycleRecord>.self, from: Data(cycleJSON.utf8)
        )
        #expect(page.records.first?.score?.strain == 12.7)
    }

    /// An unscored record carries no usable numbers; rendering it as zero would
    /// be the false zero this app refuses.
    @Test func onlyScoredRecordsAreAccepted() {
        #expect(WhoopDTOs.isScored("SCORED"))
        #expect(!WhoopDTOs.isScored("PENDING_SCORE"))
        #expect(!WhoopDTOs.isScored("UNSCORABLE"))
    }
}
