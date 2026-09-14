import Foundation
import Testing
@testable import Motion

struct RepCounterTests {
    /// Samples at 50 Hz: a sine on the vertical axis at `hz` and `amplitude` g
    /// with white noise of `noise` g, for `seconds`, starting at `t0`.
    private func signal(hz: Double, amplitude: Double, noise: Double, seconds: Double, t0: Double = 0) -> [RepCounter.Sample] {
        var generator = SystemRandomNumberGenerator()
        return stride(from: 0.0, to: seconds, by: 0.02).map { t in
            let jitter = Double.random(in: -noise...noise, using: &generator)
            return RepCounter.Sample(t: t0 + t, x: 0, y: 0, z: amplitude * sin(2 * .pi * hz * t) + jitter)
        }
    }
    private func count(_ samples: [RepCounter.Sample], counter: RepCounter = RepCounter()) -> Int {
        var counter = counter
        for sample in samples { _ = counter.add(sample) }
        return counter.reps
    }

    @Test func tenSlowCurlsCountTen() {
        // Two seconds of settling then ten cycles at 1 Hz.
        let quiet = signal(hz: 0, amplitude: 0, noise: 0.02, seconds: 2)
        let reps = signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 10, t0: 2)
        #expect(count(quiet + reps) == 10)
    }

    @Test func tinyMovementCountsNothing() {
        #expect(count(signal(hz: 1, amplitude: 0.08, noise: 0.02, seconds: 12)) == 0)
    }

    @Test func fastJitterCountsNothing() {
        #expect(count(signal(hz: 3, amplitude: 0.4, noise: 0.05, seconds: 12)) == 0)
    }

    @Test func oneSlowPushCountsNothing() {
        // One ten second cycle: five seconds out and five back, far slower than
        // a rep. Its rise-to-fall half cycle runs past `maxPeriod / 2`.
        #expect(count(signal(hz: 0.1, amplitude: 0.5, noise: 0.02, seconds: 12)) == 0)
    }

    @Test func settlingSwallowsTheFirstSecond() {
        // Cycles start at once; the first second is the person picking up the weight.
        #expect(count(signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 9)) == 8)
    }

    @Test func resetStartsOver() {
        var counter = RepCounter()
        for sample in signal(hz: 0, amplitude: 0, noise: 0.02, seconds: 2) + signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 5, t0: 2) { _ = counter.add(sample) }
        #expect(counter.reps == 5)
        counter.reset()
        #expect(counter.reps == 0)
        for sample in signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 3, t0: 7) { _ = counter.add(sample) }
        #expect(counter.reps == 2)
    }
}
