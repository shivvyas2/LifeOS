import Testing
@testable import Insights

struct AudioEnvelopeTests {
    @Test func attacksQuicklyAndReleasesGently() {
        var envelope = AudioEnvelope()
        let attack = envelope.update(target: 1, elapsed: 0.075)
        #expect(attack > 0.6 && attack < 0.65)
        let release = envelope.update(target: 0, elapsed: 0.075)
        #expect(release > attack * 0.7)
        for _ in 0..<120 { envelope.update(target: 0, elapsed: 1.0 / 60) }
        #expect(envelope.value < 0.001)
    }
    @Test func sameElapsedTimeProducesSameMotionAtDifferentFrameRates() {
        var thirty = AudioEnvelope()
        var sixty = AudioEnvelope()
        for _ in 0..<30 { thirty.update(target: 0.8, elapsed: 1.0 / 30) }
        for _ in 0..<60 { sixty.update(target: 0.8, elapsed: 1.0 / 60) }
        #expect(abs(thirty.value - sixty.value) < 0.00001)
    }
    @Test func invalidSamplesAndDecibelsStayBounded() {
        var envelope = AudioEnvelope()
        #expect(envelope.update(target: .nan, elapsed: 0.1) == 0)
        #expect(envelope.update(target: 100, elapsed: -1) == 0)
        #expect(envelope.update(target: 100, elapsed: 1) <= 1)
        #expect(AudioEnvelope.level(decibels: -160) == 0)
        #expect(AudioEnvelope.level(decibels: 0) == 1)
        #expect(AudioEnvelope.level(decibels: -.infinity) == 0)
    }
}
