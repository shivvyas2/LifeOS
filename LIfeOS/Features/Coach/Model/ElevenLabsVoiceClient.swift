import Foundation
import AVFoundation
import OSLog
import Insights

enum VoiceSynthesisError: Error, Equatable {
    case notConfigured
    case remoteFailed
    case empty
}

/// ElevenLabs text to speech. The API key is passed in, never stored here,
/// never logged.
///
/// Speech is billed per character, so the text is cleaned and capped before it
/// is sent: an assistant reply that runs long is a reply worth reading rather
/// than hearing, and paying to narrate markdown the screen already stripped
/// would be paying twice for a formatting bug.
nonisolated enum ElevenLabsVoiceClient {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "speech")

    /// Roughly ninety seconds of speech. Past this the reply is something to
    /// read, and the meter keeps running either way.
    static let maxCharacters = 1_200

    static func speech(for text: String, voice: AssistantVoice, apiKey: String) async throws -> Data {
        let spoken = spokenText(from: text)
        guard !spoken.isEmpty else { throw VoiceSynthesisError.empty }

        var request = URLRequest(
            url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice.voiceID)")!
        )
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": spoken,
            // Flash is the low latency model. A coach that answers in speech
            // three seconds after the text has already been read is not
            // answering, it is repeating.
            "model_id": "eleven_flash_v2_5",
            // Lower stability and a little style let the delivery move the
            // way a person's does; a flat, perfectly stable read is the sound
            // of text to speech. Speaker boost keeps the voice present at
            // phone volume, and text normalisation says a number out loud
            // rather than spelling it.
            "voice_settings": ["stability": 0.35, "similarity_boost": 0.8, "style": 0.3, "use_speaker_boost": true],
            "apply_text_normalization": "auto",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            log.error("elevenlabs tts failed status=\(status, privacy: .public)")
            throw VoiceSynthesisError.remoteFailed
        }
        guard !data.isEmpty else { throw VoiceSynthesisError.empty }
        return data
    }

    /// What is actually sent to be spoken.
    ///
    /// Truncated on a sentence boundary rather than mid word, because a voice
    /// stopping in the middle of a number sounds like a fault rather than a
    /// limit.
    static func spokenText(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxCharacters else { return cleaned }

        let clipped = String(cleaned.prefix(maxCharacters))
        if let lastStop = clipped.lastIndex(where: { ".!?".contains($0) }) {
            return String(clipped[...lastStop])
        }
        if let lastSpace = clipped.lastIndex(of: " ") {
            return String(clipped[..<lastSpace])
        }
        return clipped
    }
}

/// One passage of audio and which segment of the track it belongs to.
struct VoiceSegment {
    let index: Int
    let audio: Data
}

/// Plays what the clients return, in order.
///
/// Holds the player because `AVAudioPlayer` stops the moment it is
/// deallocated, which is the classic way a sound plays for a tenth of a second
/// and no longer. Plays a queue so a narration of several passages is one
/// `isSpeaking` from first start to last end, and tells the screen which
/// passage has just begun so the section it belongs to can come up with it.
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    private(set) var level: CGFloat = 0
    /// Called the moment a segment begins to play, with its index.
    var onSegmentStart: ((Int) -> Void)?
    /// Called once, when the last queued segment has ended or playback was stopped.
    var onFinish: (() -> Void)?

    private var player: AVAudioPlayer?
    private var meteringTask: Task<Void, Never>?
    private var queue: [VoiceSegment] = []

    /// Starts a fresh narration. Anything playing stops first.
    func play(_ segments: [VoiceSegment]) {
        stop(notifying: false)
        queue = segments
        playNext()
    }

    /// Adds passages to a narration already under way. If nothing is playing
    /// (the earlier passages have all ended), they start at once.
    func append(_ segments: [VoiceSegment]) {
        queue.append(contentsOf: segments)
        if player == nil { playNext() }
    }

    /// One passage, as the old single-line voice used it.
    func play(_ data: Data) { play([VoiceSegment(index: 0, audio: data)]) }

    func stop() { stop(notifying: true) }

    private func stop(notifying: Bool) {
        let wasSpeaking = isSpeaking || !queue.isEmpty
        meteringTask?.cancel()
        meteringTask = nil
        level = 0
        player?.stop()
        player = nil
        queue = []
        isSpeaking = false
        // Handed back so a podcast or a playlist returns to full volume rather
        // than staying ducked until the app is killed.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if notifying, wasSpeaking { onFinish?() }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            if isSpeaking { stop(notifying: true) }
            return
        }
        let segment = queue.removeFirst()
        do {
            // Spoken word, so it ducks other audio rather than stopping it, and
            // it plays through the speaker rather than the earpiece.
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(data: segment.audio)
            player.delegate = self
            self.player = player
            player.isMeteringEnabled = true
            guard player.play() else { playNext(); return }
            isSpeaking = true
            onSegmentStart?(segment.index)
            meteringTask?.cancel()
            meteringTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let player = self.player else { break }
                    guard player.isPlaying else { break }
                    player.updateMeters()
                    self.level = CGFloat(AudioEnvelope.level(decibels: Double(player.averagePower(forChannel: 0))))
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        } catch {
            // A passage that cannot be decoded is skipped, not fatal: the
            // next one still plays and the screen still fills.
            playNext()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // A delayed completion from an old player must not advance a newer narration.
        let finished = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == finished else { return }
            self.player = nil
            self.level = 0
            if !self.queue.isEmpty {
                // A breath between passages, the pause a person takes before
                // the next thought. Back to back, two passages run together
                // into one long sentence.
                try? await Task.sleep(for: .milliseconds(350))
                guard self.player == nil else { return }
            }
            self.playNext()
        }
    }
}
