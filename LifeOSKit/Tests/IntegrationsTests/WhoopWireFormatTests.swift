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

    /// light + SWS + REM is the direct measure. The fixture's stages are 10ms each,
    /// so the sum is 30ms, which floors to 0 minutes, while in_bed - awake would
    /// give 400. The two disagreeing is the whole point of the change.
    @Test func asleepTimeSumsTheStagesWhenTheyArePresent() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
        )
        let record = try #require(page.records.first)
        #expect(WhoopSleepMath.asleepMinutes(from: record.score?.stage_summary) == 0)
    }

    @Test func asleepTimeFallsBackToInBedMinusAwakeWhenStagesAreMissing() {
        let stages = WhoopDTOs.SleepRecord.Score.Stages(
            total_in_bed_time_milli: 25_200_000,
            total_awake_time_milli: 1_200_000,
            total_light_sleep_time_milli: nil,
            total_rem_sleep_time_milli: nil,
            total_slow_wave_sleep_time_milli: nil,
            total_no_data_time_milli: nil,
            sleep_cycle_count: nil,
            disturbance_count: nil
        )
        #expect(WhoopSleepMath.asleepMinutes(from: stages) == 400)
    }

    @Test func asleepTimeIsNilWhenThereIsNothingToComputeFrom() {
        #expect(WhoopSleepMath.asleepMinutes(from: nil) == nil)
    }

    /// A nap is not the night's sleep and must not overwrite it, but it is still a
    /// real record and is no longer thrown away.
    @Test func napsAreReturnedAndFlagged() throws {
        let json = #"{"records":[{"id":"nap-1","start":"2026-08-10T14:00:00Z","end":"2026-08-10T14:30:00Z","nap":true,"score_state":"SCORED","score":null}],"next_token":null}"#
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(json.utf8)
        )
        #expect(page.records.first?.nap == true)
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

    @Test func recoveryCarriesSpO2AndSkinTemperature() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.RecoveryRecord>.self, from: Data(recoveryJSON.utf8)
        )
        let score = try #require(page.records.first?.score)
        #expect(score.spo2_percentage == 97.2)
        #expect(score.skin_temp_celsius == 33.1)
    }

    @Test func sleepCarriesStagesRespirationAndNeed() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
        )
        let score = try #require(page.records.first?.score)
        #expect(score.respiratory_rate == 14.2)
        #expect(score.sleep_efficiency_percentage == 91)
        #expect(score.sleep_needed?.baseline_milli == 27_000_000)

        let stages = try #require(score.stage_summary)
        #expect(stages.total_light_sleep_time_milli == 10)
        #expect(stages.total_rem_sleep_time_milli == 10)
        #expect(stages.total_slow_wave_sleep_time_milli == 10)
        #expect(stages.disturbance_count == 3)
    }

    @Test func cycleCarriesEnergyAndHeartRates() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.CycleRecord>.self, from: Data(cycleJSON.utf8)
        )
        let score = try #require(page.records.first?.score)
        #expect(score.kilojoule == 9000.5)
        #expect(score.average_heart_rate == 70)
        #expect(score.max_heart_rate == 170)
    }

    /// 9000.5 kJ / 4.184 = 2151.17 kcal. The divisor is exact, not 4.2.
    @Test func kilojoulesConvertToKilocalories() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.CycleRecord>.self, from: Data(cycleJSON.utf8)
        )
        let kilojoule = try #require(page.records.first?.score?.kilojoule)
        #expect(abs(kilojoule / 4.184 - 2151.17) < 0.01)
    }

    @Test func sleepCarriesConsistencyDebtAndCycleCount() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
        )
        let score = try #require(page.records.first?.score)
        #expect(score.sleep_consistency_percentage == 70)
        #expect(score.sleep_needed?.need_from_sleep_debt_milli == 100)
        #expect(score.stage_summary?.total_no_data_time_milli == 0)
        #expect(score.stage_summary?.sleep_cycle_count == 5)
    }

    /// Whoop reports when a recovery score is still calibrating. That is not a low
    /// score, and the two must not be collapsed.
    @Test func recoveryCarriesItsCalibratingFlag() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.RecoveryRecord>.self, from: Data(recoveryJSON.utf8)
        )
        #expect(page.records.first?.score?.user_calibrating == false)
    }

    @Test func sleepSampleCarriesTheNewFieldsThrough() {
        let sample = WhoopSleepSample(
            start: .now, end: .now, performancePercentage: 88,
            consistencyPercentage: 70, sleepDebtMinutes: 12,
            asleepMinutes: 400, noDataMinutes: 0, sleepCycleCount: 5
        )
        #expect(sample.consistencyPercentage == 70)
        #expect(sample.sleepDebtMinutes == 12)
        #expect(sample.sleepCycleCount == 5)
    }

    /// Derived from Whoop's published v2 response sample, NOT captured from a live
    /// call like the three fixtures above. A decode failure here means the
    /// published sample was idealised, not that the app guessed.
    private let workoutJSON = """
    {"records":[{"id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","v1_id":1043,"user_id":9012,
      "created_at":"2022-04-24T11:25:44.774Z","updated_at":"2022-04-24T14:25:44.774Z",
      "start":"2022-04-24T02:25:44.774Z","end":"2022-04-24T10:25:44.774Z",
      "timezone_offset":"-05:00","sport_name":"running","score_state":"SCORED",
      "score":{"strain":8.2463,"average_heart_rate":123,"max_heart_rate":146,
               "kilojoule":1569.34033203125,"percent_recorded":100,
               "distance_meter":1772.77035916,"altitude_gain_meter":46.64384460449,
               "altitude_change_meter":-0.781372010707855,"zone_durations":{}},
      "sport_id":1}],
     "next_token":null}
    """

    @Test func workoutFieldsDecode() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.WorkoutRecord>.self, from: Data(workoutJSON.utf8)
        )
        let record = try #require(page.records.first)
        #expect(record.id == "ecfc6a15-4661-442f-a9a4-f160dd7afae8")
        #expect(record.sport_name == "running")
        #expect(record.sport_id == 1)
        #expect(record.score?.strain == 8.2463)
        #expect(record.score?.average_heart_rate == 123)
        #expect(record.score?.distance_meter == 1772.77035916)
        #expect(record.score?.altitude_gain_meter == 46.64384460449)
        #expect(record.score?.percent_recorded == 100)
    }

    /// 1569.34033203125 kJ / 4.184 = 375.08 kcal.
    @Test func workoutEnergyConvertsToKilocalories() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.WorkoutRecord>.self, from: Data(workoutJSON.utf8)
        )
        let kilojoule = try #require(page.records.first?.score?.kilojoule)
        #expect(abs(kilojoule / 4.184 - 375.08) < 0.01)
    }

    /// The sample spans 02:25 to 10:25, which is 8 hours.
    @Test func workoutDurationComesFromItsInterval() {
        let start = Date(timeIntervalSince1970: 0)
        let sample = WhoopWorkoutSample(externalID: "w", start: start,
                                        end: start.addingTimeInterval(8 * 3600),
                                        sportName: "running")
        #expect(sample.durationMinutes == 480)
    }

    private let bodyJSON = """
    {"height_meter":1.8288,"weight_kilogram":90.7185,"max_heart_rate":200}
    """

    @Test func bodyMeasurementDecodes() throws {
        let body = try WhoopClient.decoder.decode(
            WhoopDTOs.BodyMeasurement.self, from: Data(bodyJSON.utf8)
        )
        #expect(body.height_meter == 1.8288)
        #expect(body.weight_kilogram == 90.7185)
        #expect(body.max_heart_rate == 200)
    }

    @Test func aWorkoutPayloadCarriesItsZoneDurations() throws {
        let json = """
        {
          "id": "ecfc6a15-4661-442f-a9a4-f160dd7afae8",
          "start": "2026-08-25T10:00:00.000Z",
          "end": "2026-08-25T11:32:00.000Z",
          "sport_name": "cycling",
          "score_state": "SCORED",
          "score": {
            "strain": 11.4,
            "kilojoule": 1569.34,
            "average_heart_rate": 141,
            "max_heart_rate": 172,
            "percent_recorded": 100.0,
            "zone_durations": {
              "zone_zero_milli": 300000,
              "zone_one_milli": 600000,
              "zone_two_milli": 900000,
              "zone_three_milli": 900000,
              "zone_four_milli": 600000,
              "zone_five_milli": 300000
            }
          }
        }
        """.data(using: .utf8)!

        let record = try WhoopClient.decoder.decode(WhoopDTOs.WorkoutRecord.self, from: json)
        let sample = try #require(record.sample)

        // 300000ms = 5min, 600000 = 10, 900000 = 15
        #expect(sample.zoneMinutes == [5, 10, 15, 15, 10, 5])
    }

    @Test func aWorkoutPayloadWithoutZoneDurationsDecodesToNil() throws {
        let json = """
        {
          "id": "abc", "start": "2026-08-25T10:00:00.000Z",
          "end": "2026-08-25T11:00:00.000Z", "sport_name": "running",
          "score_state": "SCORED", "score": { "strain": 8.0 }
        }
        """.data(using: .utf8)!

        let record = try WhoopClient.decoder.decode(WhoopDTOs.WorkoutRecord.self, from: json)
        let sample = try #require(record.sample)

        #expect(sample.zoneMinutes == nil)
    }

    /// The fixture that exposed this pins it: an empty `zone_durations` object
    /// means Whoop reported no zone data, not that all six zones measured
    /// zero. `[0, 0, 0, 0, 0, 0]` would assert a reading that never happened.
    @Test func anEmptyZoneDurationsObjectDecodesToNil() throws {
        let page = try WhoopClient.decoder.decode(
            WhoopDTOs.Page<WhoopDTOs.WorkoutRecord>.self, from: Data(workoutJSON.utf8)
        )
        let sample = try #require(page.records.first?.sample)
        #expect(sample.zoneMinutes == nil)
    }

    /// A partially populated object is a genuine reading: Whoop did report
    /// zone data, so the absent members are real zeroes, not missing ones.
    @Test func aPartiallyPopulatedZoneDurationsObjectStillReportsWithZeroesForTheRest() throws {
        let json = """
        {
          "id": "partial-zone", "start": "2026-08-25T10:00:00.000Z",
          "end": "2026-08-25T11:00:00.000Z", "sport_name": "running",
          "score_state": "SCORED",
          "score": { "zone_durations": { "zone_three_milli": 1200000 } }
        }
        """.data(using: .utf8)!

        let record = try WhoopClient.decoder.decode(WhoopDTOs.WorkoutRecord.self, from: json)
        let sample = try #require(record.sample)

        #expect(sample.zoneMinutes == [0, 0, 0, 20, 0, 0])
    }

    @Test func aSleepPayloadCarriesEveryNeedComponent() throws {
        let json = """
        {
          "id": "s1", "cycle_id": 1,
          "start": "2026-08-25T23:00:00.000Z",
          "end": "2026-08-26T06:40:00.000Z",
          "nap": false, "score_state": "SCORED",
          "score": {
            "sleep_needed": {
              "baseline_milli": 27395716,
              "need_from_sleep_debt_milli": 1260000,
              "need_from_recent_strain_milli": 480000,
              "need_from_recent_nap_milli": -600000
            },
            "stage_summary": {
              "total_in_bed_time_milli": 27600000,
              "total_awake_time_milli": 1320000,
              "total_light_sleep_time_milli": 11400000,
              "total_rem_sleep_time_milli": 3720000,
              "total_slow_wave_sleep_time_milli": 4800000,
              "total_no_data_time_milli": 0,
              "sleep_cycle_count": 4,
              "disturbance_count": 9
            }
          }
        }
        """.data(using: .utf8)!

        let sample = try WhoopClient.decoder
            .decode(WhoopDTOs.SleepRecord.self, from: json).sample

        #expect(sample.needFromStrainMinutes == 8)     // 480000ms
        // Negative by definition: a recent nap reduces need. The sign is kept.
        #expect(sample.needFromNapMinutes == -10)      // -600000ms
        #expect(sample.sleepDebtMinutes == 21)
    }
}
