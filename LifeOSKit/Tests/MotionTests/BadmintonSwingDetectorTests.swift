import Testing
import AppSurfaces
@testable import Motion

struct BadmintonSwingDetectorTests {
    private func frame(_ t: Double = 0) -> WristFrame {
        WristFrame(t: t, x: 0, y: 0, z: 0, w: 1)
    }

    @Test func detectsSettledRotationBurstAndKeepsFrames() {
        var detector = BadmintonSwingDetector(profile: .init(motionEnabled: true))
        var detected = false
        for index in 0..<100 {
            let t = Double(index) * 0.02
            let active = t >= 1.2 && t < 1.44
            detected = detector.add(.init(time: t, acceleration: active ? 1.4 : 0.05,
                                          rotation: active ? 7.0 : 0.5, frame: frame())) || detected
        }
        #expect(detected)
        #expect(detector.analysis.events.count == 1)
        if let event = detector.analysis.events.first {
            #expect(event.peakRotation == 7)
            #expect(event.frames.count > 1)
        }
    }

    @Test func aSwingKeepsItsMeanForearmTwist() {
        var detector = BadmintonSwingDetector(profile: .init(motionEnabled: true))
        for index in 0..<100 {
            let t = Double(index) * 0.02
            let active = t >= 1.2 && t < 1.44
            _ = detector.add(.init(time: t, acceleration: active ? 1.4 : 0.05, rotation: active ? 7.0 : 0.5,
                                   frame: frame(), twist: active ? -3.0 : 0))
        }
        let twist = detector.analysis.events.first?.twist
        // Settling samples at the end of the burst carry no twist, so the
        // mean sits between them and the burst's -3, and keeps its sign.
        #expect(twist.map { $0 < -1 && $0 >= -3 } == true)
    }

    @Test func gapsInterruptAndInvalidQuaternionIsRejected() {
        var detector = BadmintonSwingDetector()
        _ = detector.add(.init(time: 0, acceleration: 0, rotation: 0, frame: frame()))
        _ = detector.add(.init(time: 1, acceleration: 0, rotation: 0, frame: frame()))
        #expect(detector.analysis.interrupted)
        _ = detector.add(.init(time: 1.02, acceleration: 1, rotation: 5,
                               frame: .init(t: 0, x: 0, y: 0, z: 0, w: 0)))
        #expect(detector.analysis.interrupted)
        #expect(detector.analysis.events.isEmpty)
    }
}
