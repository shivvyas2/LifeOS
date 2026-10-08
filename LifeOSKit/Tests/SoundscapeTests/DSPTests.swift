import Testing
import Foundation
@testable import Soundscape

@Suite struct DSPTests {
    let sr = 48_000.0

    func run(_ layer: Layer, midi: Int = 60, seconds: Double = 2, brightness: Double = 0.6) -> [Double] {
        var voice = Voice()
        var noise = NoiseBank(seed: 1)
        let buffers = UnsafeMutablePointer<Float>.allocate(capacity: 8 * Voice.pluckSlotLength)
        defer { buffers.deallocate() }
        buffers.initialize(repeating: 0, count: 8 * Voice.pluckSlotLength)
        voice.start(NoteEvent(layer: layer, midi: midi, velocity: 0.8, offset: 0, duration: 1),
                    sampleRate: sr, breathing: false, pluckSlot: 0, pluckBuffers: buffers, noise: &noise)
        let coef = 1 - exp(-2 * Double.pi * 1500 / sr)
        return (0..<Int(seconds * sr)).map { _ in
            voice.sample(sampleRate: sr, padCoef: coef, brightness: brightness, pluckBuffers: buffers, noise: &noise)
        }
    }

    @Test(arguments: [Layer.pad, .bell, .pluck, .pulse, .drone])
    func voicesStayFiniteAndBounded(_ layer: Layer) {
        for midi in [24, 48, 72, 100] {
            let out = run(layer, midi: midi)
            #expect(out.allSatisfy { $0.isFinite && abs($0) <= 1.5 })
            #expect(out.contains { abs($0) > 0.01 }, "\(layer) \(midi) is silent")
        }
    }

    @Test func struckVoicesDieAway() {
        for layer in [Layer.bell, .pluck, .pulse] {
            var voice = Voice(); var noise = NoiseBank(seed: 2)
            let buffers = UnsafeMutablePointer<Float>.allocate(capacity: 8 * Voice.pluckSlotLength)
            defer { buffers.deallocate() }
            buffers.initialize(repeating: 0, count: 8 * Voice.pluckSlotLength)
            voice.start(NoteEvent(layer: layer, midi: 60, velocity: 1, offset: 0, duration: 0),
                        sampleRate: sr, breathing: false, pluckSlot: 0, pluckBuffers: buffers, noise: &noise)
            for _ in 0..<Int(12 * sr) { _ = voice.sample(sampleRate: sr, padCoef: 0.1, brightness: 0.5, pluckBuffers: buffers, noise: &noise) }
            #expect(!voice.active, "\(layer) never released its voice")
        }
    }

    @Test func aHeldPadReleasesAfterItsDuration() {
        let out = run(.pad, seconds: 20)
        let early = out[Int(2 * sr)..<Int(3 * sr)].map(abs).max()!
        let late = out[Int(19 * sr)..<Int(20 * sr)].map(abs).max()!
        #expect(late < early * 0.05)
    }

    @Test func frequencyIsConcertPitch() {
        #expect(abs(Voice.frequency(midi: 69) - 440) < 1e-9)
        #expect(abs(Voice.frequency(midi: 57) - 220) < 1e-9)
    }

    @Test(arguments: [TextureKind.rain, .wind, .brown, .hiss])
    func texturesAreAudibleAndBounded(_ kind: TextureKind) {
        var noise = NoiseBank(seed: 3)
        let out = (0..<Int(2 * sr)).map { _ in noise.texture(kind, sampleRate: sr) }
        #expect(out.allSatisfy { $0.0.isFinite && $0.1.isFinite && abs($0.0) < 2 && abs($0.1) < 2 })
        #expect(out.contains { abs($0.0) > 0.01 })
        #expect(out.map(\.0) != out.map(\.1), "texture is mono")
    }

    @Test func theBedMovesFromPinkToBrown() {
        var a = NoiseBank(seed: 4); var b = NoiseBank(seed: 4)
        let pink = (0..<48_000).map { _ in a.bed(colour: 0).0 }
        let brown = (0..<48_000).map { _ in b.bed(colour: 1).0 }
        // Brown noise moves slower: smaller sample-to-sample steps for its size.
        func roughness(_ x: [Double]) -> Double {
            let steps = zip(x.dropFirst(), x).map { abs($0 - $1) }.reduce(0, +)
            return steps / max(1e-9, x.map(abs).reduce(0, +))
        }
        #expect(roughness(brown) < roughness(pink))
    }

    @Test func reverbIsStableAndHasATail() {
        var reverb = Reverb(sampleRate: sr)
        var tail: Float = 0
        for i in 0..<Int(4 * sr) {
            let x: Float = i < 100 ? 1 : 0
            let (l, r) = reverb.process(x, x, size: 1)
            #expect(l.isFinite && r.isFinite && abs(l) < 4 && abs(r) < 4)
            if i > Int(0.5 * sr), i < Int(sr) { tail = max(tail, abs(l)) }
        }
        #expect(tail > 1e-4)
    }
}
