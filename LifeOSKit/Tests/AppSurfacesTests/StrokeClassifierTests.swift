import Foundation
import Testing
@testable import AppSurfaces

struct StrokeClassifierTests {
    func event(_ id: Int, twist: Double?, peak: Double = 6) -> SwingEvent {
        SwingEvent(id: id, time: Double(id) * 10, duration: 0.4, peakRotation: peak, peakAcceleration: 1.4,
                   frames: [], twist: twist)
    }

    @Test func withNoTagsNothingIsCalled() {
        let events = [event(0, twist: 3), event(1, twist: -3)]
        #expect(StrokeClassifier.convention(events: events, tags: BadmintonShotTags()) == nil)
        #expect(StrokeClassifier.stroke(of: events[0], convention: nil, tags: BadmintonShotTags()) == nil)
    }

    @Test func tagsTeachWhichSignIsAForehand() {
        let events = [event(0, twist: -3), event(1, twist: -2.5), event(2, twist: 2.8), event(3, twist: -4)]
        var tags = BadmintonShotTags()
        tags[0] = BadmintonShotTag(stroke: .forehand)
        tags[2] = BadmintonShotTag(stroke: .backhand)
        let convention = StrokeClassifier.convention(events: events, tags: tags)
        #expect(convention == -1)
        // The untagged swings are called by the learned convention.
        #expect(StrokeClassifier.stroke(of: events[1], convention: convention, tags: tags) == .forehand)
        #expect(StrokeClassifier.stroke(of: events[3], convention: convention, tags: tags) == .forehand)
    }

    @Test func aTagAlwaysBeatsTheGuess() {
        let events = [event(0, twist: 3)]
        var tags = BadmintonShotTags()
        tags[0] = BadmintonShotTag(stroke: .backhand)
        #expect(StrokeClassifier.stroke(of: events[0], convention: 1, tags: tags) == .backhand)
    }

    @Test func aSmallTwistIsTooCloseToCall() {
        #expect(StrokeClassifier.stroke(of: event(0, twist: 0.3), convention: 1, tags: BadmintonShotTags()) == nil)
        #expect(StrokeClassifier.stroke(of: event(0, twist: nil), convention: 1, tags: BadmintonShotTags()) == nil)
    }

    @Test func contradictoryTagsTeachNothing() {
        let events = [event(0, twist: 3), event(1, twist: 3)]
        var tags = BadmintonShotTags()
        tags[0] = BadmintonShotTag(stroke: .forehand)
        tags[1] = BadmintonShotTag(stroke: .backhand)
        #expect(StrokeClassifier.convention(events: events, tags: tags) == nil)
    }

    @Test func theSummaryComparesTheTwoSides() {
        let events = [event(0, twist: 3, peak: 8), event(1, twist: 3, peak: 6), event(2, twist: -3, peak: 4),
                      event(3, twist: 0.1), event(4, twist: 3)]
        var tags = BadmintonShotTags()
        tags[4] = BadmintonShotTag(notAShot: true)
        tags[0] = BadmintonShotTag(type: .smash)
        let summary = StrokeClassifier.summary(events: events, convention: 1, tags: tags)
        #expect(summary.forehand.count == 2)
        #expect(summary.backhand.count == 1)
        #expect(summary.unclear == 1)
        #expect(summary.forehand.averagePeak == 7)
        #expect(summary.backhand.averagePeak == 4)
        #expect(summary.stronger == .forehand)
        #expect(summary.types[.smash] == 1)
    }

    @Test func theFirstSwingAfterAPauseIsTheServe() {
        let events = [event(0, twist: 3, peak: 9), event(1, twist: 3, peak: 9)]
        // Ten seconds apart, so each opens its own rally.
        #expect(StrokeClassifier.opensRally(events[0], in: events))
        #expect(StrokeClassifier.opensRally(events[1], in: events))
        let rally = [SwingEvent(id: 0, time: 10, duration: 0.4, peakRotation: 9, peakAcceleration: 1.4, frames: [], twist: 3),
                     SwingEvent(id: 1, time: 11.5, duration: 0.4, peakRotation: 9, peakAcceleration: 1.4, frames: [], twist: 3)]
        #expect(StrokeClassifier.opensRally(rally[0], in: rally))
        #expect(!StrokeClassifier.opensRally(rally[1], in: rally))
        #expect(StrokeClassifier.serve(of: rally[1], in: rally, convention: 1, tags: BadmintonShotTags()) == nil)
    }

    @Test func aGentleOrBackhandOpenerIsShortAndAFastForehandIsLong() {
        let gentle = event(0, twist: 3, peak: 4.8)
        let backhand = event(0, twist: -3, peak: 9)
        let fast = event(0, twist: 3, peak: 9)
        #expect(StrokeClassifier.serve(of: gentle, in: [gentle], convention: 1, tags: BadmintonShotTags()) == .shortServe)
        #expect(StrokeClassifier.serve(of: backhand, in: [backhand], convention: 1, tags: BadmintonShotTags()) == .shortServe)
        #expect(StrokeClassifier.serve(of: fast, in: [fast], convention: 1, tags: BadmintonShotTags()) == .longServe)
    }

    @Test func aTagDecidesTheServe() {
        let fast = event(0, twist: 3, peak: 9)
        var tags = BadmintonShotTags()
        tags[0] = BadmintonShotTag(type: .shortServe)
        #expect(StrokeClassifier.serve(of: fast, in: [fast], convention: 1, tags: tags) == .shortServe)
        tags[0] = BadmintonShotTag(type: .smash)
        #expect(StrokeClassifier.serve(of: fast, in: [fast], convention: 1, tags: tags) == nil)
        tags[0] = BadmintonShotTag(notAShot: true)
        #expect(StrokeClassifier.serve(of: fast, in: [fast], convention: 1, tags: tags) == nil)
    }

    @Test func anOldServeTagStillDecodes() throws {
        let data = Data(#"{"byEvent":{"0":{"type":"serve","notAShot":false}}}"#.utf8)
        let tags = try JSONDecoder().decode(BadmintonShotTags.self, from: data)
        #expect(tags[0]?.type == .serve)
        #expect(!BadmintonShotType.taggable.contains(.serve))
    }

    @Test func tagsSurviveStorage() throws {
        var tags = BadmintonShotTags()
        tags[3] = BadmintonShotTag(stroke: .backhand, type: .drop)
        let back = try JSONDecoder().decode(BadmintonShotTags.self, from: JSONEncoder().encode(tags))
        #expect(back == tags)
        #expect(back[3]?.type == .drop)
    }
}
