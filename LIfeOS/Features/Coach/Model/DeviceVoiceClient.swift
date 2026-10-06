import AVFoundation
import Foundation

/// Apple's on-device voice, rendered to audio data rather than spoken live,
/// so the same `VoicePlayer` queue carries it and the screen's reveal is
/// driven the same way. The fallback for when the month's premium allowance
/// is spent: free, offline, and never silent.
nonisolated enum DeviceVoiceClient {
    enum Failure: Error { case noAudio }

    /// The best installed voice for the locale: premium, then enhanced, then
    /// whatever the system has.
    static func voice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let language = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(String(language.prefix(2)))
        }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    static func speech(for text: String, locale: Locale = .current) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let synthesizer = AVSpeechSynthesizer()
        let collector = BufferCollector()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                guard let buffer = buffer as? AVAudioPCMBuffer else { return }
                if buffer.frameLength == 0 {
                    // The empty buffer is the end marker.
                    if collector.finish() { continuation.resume() }
                    return
                }
                collector.add(buffer)
            }
        }

        guard let format = collector.format, !collector.pcm.isEmpty else { throw Failure.noAudio }
        return Self.wav(pcm: collector.pcm, format: format)
    }

    /// Gathers the synthesiser's buffers; a class so the write callback,
    /// which is not `Sendable`, can append without capturing inout state.
    private final class BufferCollector: @unchecked Sendable {
        private(set) var pcm = Data()
        private(set) var format: AVAudioFormat?
        private var finished = false
        private let lock = NSLock()

        func add(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            format = buffer.format
            pcm.append(DeviceVoiceClient.bytes(of: buffer))
        }

        /// True the first time the end marker arrives.
        func finish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    /// Interleaved sample bytes from a buffer in whatever format the
    /// synthesiser produced (float32 or int16, mono or stereo).
    private static func bytes(of buffer: AVAudioPCMBuffer) -> Data {
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        var data = Data()
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let floats = buffer.floatChannelData else { return data }
            data.reserveCapacity(frames * channels * 4)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    var sample = floats[channel][frame]
                    data.append(Data(bytes: &sample, count: 4))
                }
            }
        case .pcmFormatInt16:
            guard let ints = buffer.int16ChannelData else { return data }
            data.reserveCapacity(frames * channels * 2)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    var sample = ints[channel][frame]
                    data.append(Data(bytes: &sample, count: 2))
                }
            }
        default:
            break
        }
        return data
    }

    /// A WAV container around the samples. Format 3 is IEEE float, format 1
    /// is PCM integer; `AVAudioPlayer` reads both.
    private static func wav(pcm: Data, format: AVAudioFormat) -> Data {
        let isFloat = format.commonFormat == .pcmFormatFloat32
        let bitsPerSample: UInt16 = isFloat ? 32 : 16
        let channels = UInt16(format.channelCount)
        let sampleRate = UInt32(format.sampleRate)
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)

        var header = Data()
        func put<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; header.append(Data(bytes: &v, count: MemoryLayout<T>.size)) }
        header.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(isFloat ? 3 : 1)); put(channels); put(sampleRate); put(byteRate); put(blockAlign); put(bitsPerSample)
        header.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return header + pcm
    }
}
