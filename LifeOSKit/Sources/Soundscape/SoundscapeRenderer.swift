import Foundation
import Synchronization

/// Plays one mood. `set`, `setLight` and `chime` may be called from any
/// thread; `render` only from the audio thread (or offline). Everything the
/// render path touches is allocated in `init`.
public final class SoundscapeRenderer: @unchecked Sendable {
    public let mood: Mood
    public let sampleRate: Double
    public private(set) var isLight = false

    private static let block = 64
    private static let voiceCount = 40
    private static let pluckSlots = 8
    private static let glideSeconds = 3.0

    private let inbox = Mutex<SoundParameters?>(nil)
    private let lightRequest = Atomic<Bool>(false)
    private let chimeRequest = Atomic<Bool>(false)

    private var target: SoundParameters
    private var current: SoundParameters
    private var composer: Composer
    private var events: [NoteEvent]
    private var nextEvent = 0
    private var samplesIntoBar = 0
    private var barSamples = 0
    private let voices: UnsafeMutablePointer<Voice>
    private let pluckBuffers: UnsafeMutablePointer<Float>
    private var nextPluckSlot = 0
    private var noise: NoiseBank
    private var reverb: Reverb
    private var breathPhase = 0.0
    private var padCoef = 0.1
    private var overruns = 0
    /// The voice playing a chime, which ignores layer gains and the master.
    private var chimeVoice: Int?

    public init(mood: Mood, sampleRate: Double = 48_000, seed: UInt64 = 1, parameters: SoundParameters) {
        self.mood = mood
        self.sampleRate = sampleRate
        self.target = parameters
        self.current = parameters
        self.composer = Composer(recipe: .for(mood), seed: seed)
        self.events = []
        self.events.reserveCapacity(128)
        self.voices = .allocate(capacity: Self.voiceCount)
        self.voices.initialize(repeating: Voice(), count: Self.voiceCount)
        self.pluckBuffers = .allocate(capacity: Self.pluckSlots * Voice.pluckSlotLength)
        self.pluckBuffers.initialize(repeating: 0, count: Self.pluckSlots * Voice.pluckSlotLength)
        self.noise = NoiseBank(seed: UInt32(truncatingIfNeeded: seed &* 2_654_435_761) | 1)
        self.reverb = Reverb(sampleRate: sampleRate)
    }

    deinit {
        voices.deinitialize(count: Self.voiceCount); voices.deallocate()
        pluckBuffers.deallocate()
    }

    public func set(_ parameters: SoundParameters) { inbox.withLock { $0 = parameters } }
    public func setLight(_ on: Bool) { lightRequest.store(on, ordering: .relaxed) }
    public func chime() { chimeRequest.store(true, ordering: .relaxed) }

    public func render(seconds: Double) -> (left: [Float], right: [Float]) {
        let frames = Int(seconds * sampleRate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                render(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
            }
        }
        return (left, right)
    }

    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let began = ContinuousClock.now
        if let fresh = inbox.withLockIfAvailable({ value -> SoundParameters? in
            defer { value = nil }
            return value
        }), let parameters = fresh {
            target = parameters
        }
        isLight = lightRequest.load(ordering: .relaxed) || overruns >= 8
        if chimeRequest.exchange(false, ordering: .relaxed) {
            chimeVoice = trigger(NoteEvent(layer: .bell, midi: composer.midi(degree: composer.recipe.scale.count * 2, keyOffset: current.keyOffset),
                                           velocity: 0.9, offset: 0, duration: 0), force: true)
        }
        var done = 0
        while done < frames {
            let n = min(Self.block, frames - done)
            glide(samples: n)
            renderBlock(left + done, right + done, n)
            done += n
        }
        // Light mode after eight renders in a row that used most of their
        // time budget; it clears once renders are comfortably fast again.
        let budget = Double(frames) / sampleRate
        let took = began.duration(to: .now)
        let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) * 1e-18
        if seconds > budget * 0.7 { overruns = min(overruns + 1, 16) } else if seconds < budget * 0.3 { overruns = max(overruns - 1, 0) }
    }

    private func glide(samples: Int) {
        let c = 1 - exp(-Double(samples) / (sampleRate * Self.glideSeconds))
        func step(_ a: inout Double, _ b: Double) { a += (b - a) * c }
        step(&current.tempo, target.tempo)
        step(&current.density, target.density)
        step(&current.brightness, target.brightness)
        step(&current.reverb, target.reverb)
        step(&current.master, target.master)
        step(&current.bedColour, target.bedColour)
        current.gains += (target.gains - current.gains) * c
        if let to = target.breathPeriod {
            current.breathPeriod = (current.breathPeriod ?? to) + (to - (current.breathPeriod ?? to)) * c
        } else {
            current.breathPeriod = nil
        }
        current.keyOffset = target.keyOffset
        current.texture = target.texture
        let fc = 250 + current.brightness * current.brightness * 3500
        padCoef = 1 - exp(-2 * Double.pi * fc / sampleRate)
    }

    private func startBar() {
        composer.nextBar(current, into: &events)
        nextEvent = 0
        samplesIntoBar = 0
        barSamples = max(1, Int(current.barSeconds * sampleRate))
    }

    @discardableResult
    private func trigger(_ event: NoteEvent, force: Bool = false) -> Int? {
        if isLight, !force, event.layer == .bell || event.layer == .pluck || event.layer == .pulse { return nil }
        var pick = 0
        var quietest = Double.infinity
        for i in 0..<Self.voiceCount {
            if !voices[i].active { pick = i; break }
            if voices[i].level < quietest { quietest = voices[i].level; pick = i }
        }
        let slot = nextPluckSlot
        if event.layer == .pluck { nextPluckSlot = (nextPluckSlot + 1) % Self.pluckSlots }
        if pick == chimeVoice { chimeVoice = nil }
        voices[pick].start(event, sampleRate: sampleRate, breathing: current.breathPeriod != nil,
                           pluckSlot: slot, pluckBuffers: pluckBuffers, noise: &noise)
        return pick
    }

    private func renderBlock(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ n: Int) {
        let gains = current.gains
        let bedGain = gains[Layer.bed.rawValue]
        let textureGain = gains[Layer.texture.rawValue]
        let wet = Float(isLight ? 0 : 0.15 + 0.35 * current.reverb)
        let size = Float(current.reverb)
        for s in 0..<n {
            if samplesIntoBar >= barSamples { startBar() }
            while nextEvent < events.count, Int(events[nextEvent].offset * sampleRate) <= samplesIntoBar {
                trigger(events[nextEvent]); nextEvent += 1
            }
            samplesIntoBar += 1

            var swell = 1.0
            if let period = current.breathPeriod {
                breathPhase += 1 / (period * sampleRate)
                if breathPhase >= 1 { breathPhase -= 1 }
                let inhale = 0.4
                let x = breathPhase < inhale ? breathPhase / inhale : (breathPhase - inhale) / (1 - inhale)
                let shape = breathPhase < inhale ? 0.5 - 0.5 * cos(.pi * x) : 0.5 + 0.5 * cos(.pi * x)
                swell = 0.55 + 0.45 * shape
            }

            var l = 0.0, r = 0.0, chime = 0.0
            for i in 0..<Self.voiceCount where voices[i].active {
                let layer = voices[i].layer
                let raw = voices[i].sample(sampleRate: sampleRate, padCoef: padCoef, brightness: current.brightness,
                                           pluckBuffers: pluckBuffers, noise: &noise)
                if i == chimeVoice { chime += raw * 0.6; continue }
                var x = raw * gains[layer.rawValue]
                if layer == .pad || layer == .drone { x *= swell }
                let pan = voices[i].pan
                l += x * cos(pan * .pi / 2)
                r += x * sin(pan * .pi / 2)
            }
            if let c = chimeVoice, !voices[c].active { chimeVoice = nil }
            if bedGain > 0 {
                let (bl, br) = noise.bed(colour: current.bedColour)
                l += bl * bedGain * swell; r += br * bedGain * swell
            }
            if textureGain > 0, current.texture != .none {
                let (tl, tr) = noise.texture(current.texture, sampleRate: sampleRate)
                l += tl * textureGain; r += tr * textureGain
            }
            var fl = Float(l * 0.5), fr = Float(r * 0.5)
            if wet > 0 {
                let (rl, rr) = reverb.process(fl, fr, size: size)
                fl += rl * wet; fr += rr * wet
            }
            let master = Float(current.master)
            left[s] = 0.95 * tanh(fl * master + Float(chime))
            right[s] = 0.95 * tanh(fr * master + Float(chime))
        }
    }
}
