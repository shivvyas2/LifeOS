import Foundation
import HealthKit
import AppSurfaces

/// Live heart rate for a focus session: the Watch runs a mind-and-body
/// session (streaming every few seconds), which is discarded at the end.
@MainActor
final class FocusHeartRate {
    var onHeartRate: ((Int) -> Void)?
    private var running = false

    func start() async {
        let bridge = WatchSessionBridge.shared
        guard WatchSessionBridge.watchAvailable, !bridge.hasSession else { return }
        bridge.onFocusPacket = { [weak self] data in
            guard let packet = WatchWire.packet(from: data), let rate = packet.heartRate, (30...220).contains(rate),
                  packet.sentAt > Date.now.addingTimeInterval(-30) else { return }
            self?.onHeartRate?(rate)
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor
        running = true
        try? await WatchSessionBridge.startWatchApp(configuration)
    }

    func stop() {
        guard running else { return }
        running = false
        let bridge = WatchSessionBridge.shared
        if bridge.isFocusSession { bridge.end(after: .discard) }
        bridge.onFocusPacket = nil
    }
}
