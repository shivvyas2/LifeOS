import AVFoundation
import Soundscape

/// Hosts the soundscape on `AVAudioEngine`. Two renderers can play at once
/// so a change of mood crossfades over eight seconds.
@MainActor
final class SoundscapeEngine {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var slots: [(renderer: SoundscapeRenderer, node: AVAudioSourceNode)] = []
    private var fade: Task<Void, Never>?
    private var light = false
    private(set) var isRunning = false

    func start(mood: Mood, parameters: SoundParameters) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if slots.isEmpty { attach(mood: mood, parameters: parameters, volume: 1) }
        try engine.start()
        isRunning = true
    }

    func update(_ parameters: SoundParameters) { slots.last?.renderer.set(parameters) }

    func change(to mood: Mood, parameters: SoundParameters) {
        fade?.cancel()
        // A change during a crossfade drops the oldest voice at once.
        while slots.count > 1 { engine.detach(slots.removeFirst().node) }
        guard let old = slots.last else { return }
        old.node.volume = 1
        attach(mood: mood, parameters: parameters, volume: 0)
        let new = slots[slots.count - 1]
        fade = Task { [weak self] in
            for step in 1...40 {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                let t = Float(step) / 40
                old.node.volume = 1 - t
                new.node.volume = t
            }
            guard let self, let index = self.slots.firstIndex(where: { $0.node === old.node }) else { return }
            self.engine.detach(old.node)
            self.slots.remove(at: index)
        }
    }

    func pause() { engine.pause(); isRunning = false }

    func resume() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
        isRunning = true
    }

    func stop() {
        fade?.cancel(); fade = nil
        engine.stop()
        for slot in slots { engine.detach(slot.node) }
        slots = []
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setLight(_ on: Bool) {
        light = on
        for slot in slots { slot.renderer.setLight(on) }
    }

    func chime() { slots.last?.renderer.chime() }

    private func attach(mood: Mood, parameters: SoundParameters, volume: Float) {
        let renderer = SoundscapeRenderer(mood: mood, sampleRate: format.sampleRate,
                                          seed: UInt64.random(in: 1...UInt64.max), parameters: parameters)
        renderer.setLight(light)
        let node = Self.makeNode(renderer, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.volume = volume
        slots.append((renderer, node))
    }

    /// `nonisolated` so the render block is not main-actor isolated: the
    /// audio thread calls it, and an isolated closure would trap there.
    nonisolated private static func makeNode(_ renderer: SoundscapeRenderer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            renderer.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }
}
