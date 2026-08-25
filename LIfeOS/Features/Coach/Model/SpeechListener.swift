import Foundation
import Speech
import AVFoundation
import OSLog

private let speechLog = Logger(subsystem: "com.shivvyas.lifeos", category: "speech")

/// Microphone + speech recognition for LIFO. Failures are surfaced, never
/// silent: if the mic is refused the keyboard is the way through.
@MainActor
final class SpeechListener {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    var onError: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    func start() async {
        guard !isRunning else { return }

        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            onError?("Microphone permission is needed to talk to LIFO.")
            return
        }

        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            onError?("Microphone permission is needed to talk to LIFO.")
            return
        }

        guard recognizer?.isAvailable == true else {
            onError?("Speech recognition is not available right now.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.rms(buffer)
                Task { @MainActor in self?.onLevel?(level) }
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.request = request
            self.isRunning = true

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if result.isFinal {
                            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            self.onFinal?(text)
                        } else {
                            self.onPartial?(text)
                        }
                    }
                    if let error {
                        let ns = error as NSError
                        // Cancellation after stop() is not a failure.
                        if ns.code == 1 || ns.code == 209 || ns.code == 216 { return }
                        speechLog.error("recognition failed: \(error.localizedDescription, privacy: .public)")
                        self.onError?(error.localizedDescription)
                        self.stop()
                    }
                }
            }
        } catch {
            speechLog.error("engine failed: \(error.localizedDescription, privacy: .public)")
            onError?(error.localizedDescription)
            stop()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        onLevel?(0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        return CGFloat(min(max(rms * 8, 0), 1))
    }
}
