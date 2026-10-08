import MediaPlayer

/// The lock screen's title and play, pause and skip-phase buttons for a
/// soundscape session. Apple Music publishes its own.
@MainActor
final class FocusNowPlaying {
    private var targets: [Any] = []

    func activate(title: String, onPlay: @escaping () -> Void, onPause: @escaping () -> Void, onSkip: @escaping () -> Void) {
        clear()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        targets = [
            center.playCommand.addTarget { _ in MainActor.assumeIsolated { onPlay() }; return .success },
            center.pauseCommand.addTarget { _ in MainActor.assumeIsolated { onPause() }; return .success },
            center.nextTrackCommand.addTarget { _ in MainActor.assumeIsolated { onSkip() }; return .success },
        ]
        update(title: title, elapsed: 0, duration: nil, playing: true)
    }

    func update(title: String, elapsed: TimeInterval, duration: TimeInterval?, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Almanac",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        let center = MPRemoteCommandCenter.shared()
        for target in targets {
            center.playCommand.removeTarget(target)
            center.pauseCommand.removeTarget(target)
            center.nextTrackCommand.removeTarget(target)
        }
        targets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
