import Foundation
import AVFoundation
import OSLog

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
            "voice_settings": ["stability": 0.4, "similarity_boost": 0.75],
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

/// Plays what the client returns.
///
/// Holds the player because `AVAudioPlayer` stops the moment it is
/// deallocated, which is the classic way a sound plays for a tenth of a second
/// and no longer.
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    private var player: AVAudioPlayer?

    func play(_ data: Data) {
        stop()
        do {
            // Spoken word, so it ducks other audio rather than stopping it, and
            // it plays through the speaker rather than the earpiece.
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            self.player = player
            isSpeaking = true
            player.play()
        } catch {
            isSpeaking = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isSpeaking = false
        // Handed back so a podcast or a playlist returns to full volume rather
        // than staying ducked until the app is killed.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in stop() }
    }
}
