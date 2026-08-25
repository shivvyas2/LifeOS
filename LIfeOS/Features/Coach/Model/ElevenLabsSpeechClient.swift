import Foundation
import OSLog

/// ElevenLabs Scribe. The API key is passed in, never stored, never logged.
nonisolated enum ElevenLabsSpeechClient {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "speech")

    struct Transcript: Decodable {
        var text: String?
    }

    static func transcribe(wav: Data, apiKey: String) async throws -> String {
        let boundary = "LifeOS-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = multipartBody(wav: wav, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            log.error("elevenlabs stt failed status=\(status, privacy: .public)")
            throw SpeechTranscribeError.remoteFailed
        }
        let decoded = try JSONDecoder().decode(Transcript.self, from: data)
        let text = decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw SpeechTranscribeError.empty }
        return text
    }

    private static func multipartBody(wav: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        append("scribe_v2\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

enum SpeechTranscribeError: Error {
    case remoteFailed
    case empty
}
